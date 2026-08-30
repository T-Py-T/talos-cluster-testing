#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly WORK_ROOT="${WORK_ROOT:-${RUNNER_TEMP:-/tmp}/omarchy-arm64}"
readonly SOURCE_ROOT="${WORK_ROOT}/source"
readonly OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/dist}"
readonly MANIFEST_DIR="${OUTPUT_DIR}/manifest"
readonly ISO_REPOSITORY="${ISO_REPOSITORY:-https://github.com/omacom/omarchy-iso.git}"
readonly ISO_COMMIT="${ISO_COMMIT:-7f003b3cc9483317930e1ff2241e44262c784dd4}"
readonly ISO_FALLBACK_REPOSITORY="${ISO_FALLBACK_REPOSITORY:-https://github.com/oceanapplications/omarchy-iso.git}"
readonly ISO_FALLBACK_REF="${ISO_FALLBACK_REF:-aarch64-build-system}"
readonly OMARCHY_REPOSITORY="${OMARCHY_REPOSITORY:-https://github.com/omacom/omarchy.git}"
readonly OMARCHY_COMMIT="${OMARCHY_COMMIT:-13f18b2cb7286fb54f87daf571a031aa6af3d8f0}"
readonly OMARCHY_ARM_PR="${OMARCHY_ARM_PR:-8039}"
readonly TARGET_ARCH="aarch64"

on_error() {
  local exit_code=$?
  printf 'Build failed at line %s while running: %s\n' "${BASH_LINENO[0]}" "${BASH_COMMAND}" >&2
  exit "${exit_code}"
}
trap on_error ERR

log() {
  printf '\n[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

clone_exact() {
  local repository=$1
  local commit=$2
  local destination=$3

  rm -rf "${destination}"
  git init -q "${destination}"
  git -C "${destination}" remote add origin "${repository}"
  git -C "${destination}" fetch --depth=1 origin "${commit}"
  git -C "${destination}" checkout --detach FETCH_HEAD
}

resolve_iso_source() {
  local destination=$1

  clone_exact "${ISO_REPOSITORY}" "${ISO_COMMIT}" "${destination}"
  if [[ -f "${destination}/builder/build-iso.sh" && -f "${destination}/builder/build-omarchy-packages.sh" ]]; then
    printf '%s\n' "${ISO_COMMIT}" > "${MANIFEST_DIR}/omarchy-iso.commit"
    printf '%s\n' "${ISO_REPOSITORY}" > "${MANIFEST_DIR}/omarchy-iso.repository"
    return
  fi

  log "Pinned upstream commit does not contain the ARM builder entry points; resolving the reviewed fallback branch."
  rm -rf "${destination}"
  git clone --filter=blob:none --branch "${ISO_FALLBACK_REF}" --single-branch "${ISO_FALLBACK_REPOSITORY}" "${destination}"
  git -C "${destination}" rev-parse HEAD > "${MANIFEST_DIR}/omarchy-iso.commit"
  printf '%s\n' "${ISO_FALLBACK_REPOSITORY}" > "${MANIFEST_DIR}/omarchy-iso.repository"
}

apply_arm_fixes() {
  local repository_dir=$1
  local pr_json="${MANIFEST_DIR}/omarchy-pr-${OMARCHY_ARM_PR}.json"
  local patch_file="${MANIFEST_DIR}/omarchy-pr-${OMARCHY_ARM_PR}.patch"
  local api_url="https://api.github.com/repos/omacom/omarchy/pulls/${OMARCHY_ARM_PR}"
  local base_sha
  local head_sha

  curl --fail --location --silent --show-error \
    -H 'Accept: application/vnd.github+json' \
    "${api_url}" > "${pr_json}"
  base_sha="$(jq -er '.base.sha' "${pr_json}")"
  head_sha="$(jq -er '.head.sha' "${pr_json}")"

  git -C "${repository_dir}" fetch --depth=1 origin "${base_sha}" "${head_sha}"
  git -C "${repository_dir}" diff --binary "${base_sha}" "${head_sha}" > "${patch_file}"
  test -s "${patch_file}"

  git -C "${repository_dir}" config user.name 'Omarchy ARM64 Builder'
  git -C "${repository_dir}" config user.email 'actions@users.noreply.github.com'
  git -C "${repository_dir}" apply --3way "${patch_file}"
  git -C "${repository_dir}" add --all
  git -C "${repository_dir}" commit -m "Apply ARM64 fixes from omacom/omarchy#${OMARCHY_ARM_PR}"

  printf '%s\n' "${base_sha}" > "${MANIFEST_DIR}/omarchy-arm-pr.base"
  printf '%s\n' "${head_sha}" > "${MANIFEST_DIR}/omarchy-arm-pr.head"
  git -C "${repository_dir}" rev-parse HEAD > "${MANIFEST_DIR}/omarchy-patched.commit"
}

configure_local_omarchy_source() {
  local repository_dir=$1
  local source_url="file://${repository_dir}"
  local official_https='https://github.com/omacom/omarchy.git'
  local legacy_https='https://github.com/basecamp/omarchy.git'

  git config --global protocol.file.allow always
  git config --global --add "url.${source_url}.insteadOf" "${official_https}"
  git config --global --add "url.${source_url}.insteadOf" "${legacy_https}"

  sudo git config --system protocol.file.allow always
  sudo git config --system --add "url.${source_url}.insteadOf" "${official_https}"
  sudo git config --system --add "url.${source_url}.insteadOf" "${legacy_https}"
}

run_builder() {
  local repository_dir=$1
  local script_path=$2
  local full_path="${repository_dir}/${script_path}"
  local -a arguments=()

  test -f "${full_path}"
  chmod +x "${full_path}"

  if grep -Eq -- '(^|[[:space:]])--arch([=[:space:]]|$)' "${full_path}"; then
    arguments=(--arch "${TARGET_ARCH}")
  fi

  log "Running ${script_path} ${arguments[*]:-}"
  (
    cd "${repository_dir}"
    sudo --preserve-env=ARCH,TARGET_ARCH,OMARCHY_VERSION,OMARCHY_COMMIT,OMARCHY_REF,GITHUB_TOKEN \
      env \
      ARCH="${TARGET_ARCH}" \
      TARGET_ARCH="${TARGET_ARCH}" \
      OMARCHY_VERSION='4.0.1' \
      OMARCHY_COMMIT="$(cat "${MANIFEST_DIR}/omarchy-patched.commit")" \
      OMARCHY_REF="$(cat "${MANIFEST_DIR}/omarchy-patched.commit")" \
      bash -x "${script_path}" "${arguments[@]}"
  ) 2>&1 | tee -a "${OUTPUT_DIR}/build.log"
}

collect_iso() {
  local repository_dir=$1
  local iso_path

  iso_path="$(find "${repository_dir}" "${WORK_ROOT}" -type f -name '*.iso' -size +500M -print0 \
    | xargs -0 -r ls -1t \
    | head -n 1)"
  test -n "${iso_path}"
  install -m 0644 "${iso_path}" "${OUTPUT_DIR}/omarchy-4.0.1-aarch64.iso"
  sha256sum "${OUTPUT_DIR}/omarchy-4.0.1-aarch64.iso" \
    | tee "${OUTPUT_DIR}/omarchy-4.0.1-aarch64.iso.sha256"
}

main() {
  local iso_dir="${SOURCE_ROOT}/omarchy-iso"
  local omarchy_dir="${SOURCE_ROOT}/omarchy"

  rm -rf "${WORK_ROOT}" "${OUTPUT_DIR}"
  mkdir -p "${SOURCE_ROOT}" "${MANIFEST_DIR}"
  : > "${OUTPUT_DIR}/build.log"

  log 'Resolving pinned ISO source.'
  resolve_iso_source "${iso_dir}"

  log 'Resolving Omarchy 4.0.1.'
  clone_exact "${OMARCHY_REPOSITORY}" "${OMARCHY_COMMIT}" "${omarchy_dir}"
  printf '%s\n' "${OMARCHY_COMMIT}" > "${MANIFEST_DIR}/omarchy-4.0.1.commit"

  log "Applying the reviewed ARM64 fix set from PR #${OMARCHY_ARM_PR}."
  apply_arm_fixes "${omarchy_dir}"
  configure_local_omarchy_source "${omarchy_dir}"

  log 'Building the ARM package repository.'
  run_builder "${iso_dir}" 'builder/build-omarchy-packages.sh'

  log 'Building the ARM64 ISO.'
  run_builder "${iso_dir}" 'builder/build-iso.sh'

  log 'Collecting the ISO and immutable build manifest.'
  collect_iso "${iso_dir}"
  git --version > "${MANIFEST_DIR}/git.version"
  uname -a > "${MANIFEST_DIR}/runner.uname"
  date -u +'%Y-%m-%dT%H:%M:%SZ' > "${MANIFEST_DIR}/built-at.txt"
}

main "$@"
