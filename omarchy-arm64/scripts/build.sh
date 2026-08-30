#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../sources.env
source "$PROJECT_DIR/sources.env"

WORKSPACE="${OMARCHY_ARM64_WORKSPACE:-${RUNNER_TEMP:-/tmp}/omarchy-arm64-build}"
ARTIFACT_DIR="${OMARCHY_ARM64_ARTIFACT_DIR:-$PROJECT_DIR/artifacts}"
BUILDER_DIR="$WORKSPACE/omarchy-iso"
OMARCHY_DIR="$WORKSPACE/omarchy"
PKGS_DIR="$WORKSPACE/omarchy-pkgs"
RELEASE_METADATA="$ARTIFACT_DIR/package-release.json"

log() {
  printf '\n==> %s\n' "$*"
}

clone_at_commit() {
  local repository="$1" commit="$2" destination="$3"

  git clone --filter=blob:none --no-checkout "$repository" "$destination"
  git -C "$destination" fetch --depth=1 origin "$commit"
  git -C "$destination" checkout --detach "$commit"

  local actual
  actual="$(git -C "$destination" rev-parse HEAD)"
  [[ $actual == "$commit" ]] || {
    echo "Commit mismatch for $repository: expected $commit, got $actual" >&2
    exit 1
  }
}

[[ $(uname -m) == aarch64 ]] || {
  echo "This build must run natively on AArch64; host is $(uname -m)." >&2
  exit 1
}

rm -rf "$WORKSPACE" "$ARTIFACT_DIR"
mkdir -p "$WORKSPACE" "$ARTIFACT_DIR"

log "Checking out pinned sources"
clone_at_commit "$ISO_BUILDER_REPO" "$ISO_BUILDER_COMMIT" "$BUILDER_DIR"
clone_at_commit "$OMARCHY_REPO" "$OMARCHY_COMMIT" "$OMARCHY_DIR"
clone_at_commit "$OMARCHY_PKGS_REPO" "$OMARCHY_PKGS_COMMIT" "$PKGS_DIR"
git -C "$BUILDER_DIR" submodule update --init --recursive --depth=1

log "Verifying the Omarchy release tag and package recipes"
git -C "$OMARCHY_DIR" fetch --depth=1 origin "refs/tags/$OMARCHY_TAG:refs/tags/$OMARCHY_TAG"
[[ $(git -C "$OMARCHY_DIR" rev-list -n 1 "$OMARCHY_TAG") == "$OMARCHY_COMMIT" ]] || {
  echo "$OMARCHY_TAG does not resolve to $OMARCHY_COMMIT" >&2
  exit 1
}
for recipe in omarchy omarchy-settings; do
  grep -Fq "_commit='$OMARCHY_COMMIT'" "$PKGS_DIR/pkgbuilds/$recipe/PKGBUILD" || {
    echo "$recipe PKGBUILD is not pinned to $OMARCHY_COMMIT" >&2
    exit 1
  }
  grep -Fq "_tag='$OMARCHY_TAG'" "$PKGS_DIR/pkgbuilds/$recipe/PKGBUILD" || {
    echo "$recipe PKGBUILD is not labeled $OMARCHY_TAG" >&2
    exit 1
  }
done

log "Pinning and verifying the external AArch64 package release"
curl --fail --location --retry 5 --retry-all-errors \
  "https://api.github.com/repos/riverscn/omarchy-pkgs-aarch64/releases/tags/$OMARCHY_PKGS_RELEASE_TAG" \
  --output "$RELEASE_METADATA"

[[ $(jq -r .id "$RELEASE_METADATA") == "$OMARCHY_PKGS_RELEASE_ID" ]] || {
  echo "Package release ID changed; refusing an unreviewed rolling snapshot." >&2
  jq '{id, tag_name, target_commitish, published_at}' "$RELEASE_METADATA" >&2
  exit 1
}
[[ $(jq -r .target_commitish "$RELEASE_METADATA") == "$OMARCHY_PKGS_COMMIT" ]] || {
  echo "Package release target no longer matches $OMARCHY_PKGS_COMMIT." >&2
  jq '{id, tag_name, target_commitish, published_at}' "$RELEASE_METADATA" >&2
  exit 1
}

ASSETS_METADATA="$ARTIFACT_DIR/package-release-assets.json"
ASSETS_URL="$(jq -r .assets_url "$RELEASE_METADATA")"
ASSETS_JSONL="$WORKSPACE/package-release-assets.jsonl"
: >"$ASSETS_JSONL"
page=1
while true; do
  page_file="$WORKSPACE/package-release-assets-$page.json"
  curl --fail --location --retry 5 --retry-all-errors \
    "$ASSETS_URL?per_page=100&page=$page" --output "$page_file"
  count="$(jq 'length' "$page_file")"
  jq -c '.[]' "$page_file" >>"$ASSETS_JSONL"
  ((count < 100)) && break
  ((page += 1))
done
jq --slurp '.' "$ASSETS_JSONL" >"$ASSETS_METADATA"

KEY_URL="$(jq -r '.[] | select(.name == "omarchy-aarch64.gpg") | .browser_download_url' "$ASSETS_METADATA")"
KEY_DIGEST="$(jq -r '.[] | select(.name == "omarchy-aarch64.gpg") | .digest' "$ASSETS_METADATA")"
[[ -n $KEY_URL && $KEY_URL != null ]] || {
  echo "The package release does not contain omarchy-aarch64.gpg." >&2
  exit 1
}
curl --fail --location --retry 5 --retry-all-errors "$KEY_URL" \
  --output "$BUILDER_DIR/builder/omarchy.gpg"
if [[ $KEY_DIGEST == sha256:* ]]; then
  echo "${KEY_DIGEST#sha256:}  $BUILDER_DIR/builder/omarchy.gpg" | sha256sum --check --strict
fi
ACTUAL_FINGERPRINT="$(gpg --show-keys --with-colons "$BUILDER_DIR/builder/omarchy.gpg" | awk -F: '$1 == "fpr" {print $10; exit}')"
[[ $ACTUAL_FINGERPRINT == "$OMARCHY_SIGNING_FINGERPRINT" ]] || {
  echo "Signing key mismatch: expected $OMARCHY_SIGNING_FINGERPRINT, got $ACTUAL_FINGERPRINT" >&2
  exit 1
}

log "Patching the generic ARM builder for the pinned 4.0.1 sources"
python3 "$SCRIPT_DIR/patch-builder.py" \
  --builder "$BUILDER_DIR" \
  --release-url "$OMARCHY_PKGS_RELEASE_URL" \
  --fingerprint "$OMARCHY_SIGNING_FINGERPRINT" \
  --omarchy-ref "$OMARCHY_TAG"
git -C "$BUILDER_DIR" diff --binary >"$ARTIFACT_DIR/iso-builder.patch"

log "Building the offline AArch64 ISO"
(
  cd "$BUILDER_DIR"
  NO_BOOT_OFFER=1 ./bin/omarchy-iso-make \
    --no-cache \
    --keep-pkg-cache \
    --debug \
    --local-source "$OMARCHY_DIR" "$PKGS_DIR"
)

ISO_SOURCE="$(find "$BUILDER_DIR/release" -maxdepth 1 -type f -name '*.iso' -print -quit)"
[[ -n $ISO_SOURCE && -s $ISO_SOURCE ]] || {
  echo "No ISO was produced in $BUILDER_DIR/release." >&2
  exit 1
}
ISO_DEST="$ARTIFACT_DIR/omarchy-4.0.1-aarch64.iso"
cp --reflink=auto "$ISO_SOURCE" "$ISO_DEST"
sha256sum "$ISO_DEST" | sed "s|$ISO_DEST|$(basename "$ISO_DEST")|" >"$ARTIFACT_DIR/SHA256SUMS"

jq -n \
  --arg built_at "$(date --utc --iso-8601=seconds)" \
  --arg runner_arch "$(uname -m)" \
  --arg iso_sha256 "$(sha256sum "$ISO_DEST" | awk '{print $1}')" \
  --arg iso_builder_repo "$ISO_BUILDER_REPO" \
  --arg iso_builder_commit "$ISO_BUILDER_COMMIT" \
  --arg omarchy_repo "$OMARCHY_REPO" \
  --arg omarchy_tag "$OMARCHY_TAG" \
  --arg omarchy_commit "$OMARCHY_COMMIT" \
  --arg upstream_repo "$OMARCHY_UPSTREAM_REPO" \
  --arg upstream_commit "$OMARCHY_UPSTREAM_COMMIT" \
  --arg pkgs_repo "$OMARCHY_PKGS_REPO" \
  --arg pkgs_commit "$OMARCHY_PKGS_COMMIT" \
  --arg pkgs_release_tag "$OMARCHY_PKGS_RELEASE_TAG" \
  --argjson pkgs_release_id "$OMARCHY_PKGS_RELEASE_ID" \
  --arg signing_fingerprint "$OMARCHY_SIGNING_FINGERPRINT" \
  '{
    built_at: $built_at,
    runner_arch: $runner_arch,
    iso: {file: "omarchy-4.0.1-aarch64.iso", sha256: $iso_sha256},
    iso_builder: {repository: $iso_builder_repo, commit: $iso_builder_commit},
    omarchy: {
      repository: $omarchy_repo,
      tag: $omarchy_tag,
      commit: $omarchy_commit,
      upstream_repository: $upstream_repo,
      upstream_commit: $upstream_commit
    },
    package_repository: {
      repository: $pkgs_repo,
      source_commit: $pkgs_commit,
      release_tag: $pkgs_release_tag,
      release_id: $pkgs_release_id,
      signing_fingerprint: $signing_fingerprint
    }
  }' >"$ARTIFACT_DIR/build-manifest.json"

printf 'BUILDER_DIR=%s\nOMARCHY_DIR=%s\nISO_PATH=%s\nARTIFACT_DIR=%s\n' \
  "$BUILDER_DIR" "$OMARCHY_DIR" "$ISO_DEST" "$ARTIFACT_DIR" \
  >"$WORKSPACE/build.env"

log "Build complete: $ISO_DEST"
