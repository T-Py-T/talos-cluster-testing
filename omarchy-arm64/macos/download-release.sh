#!/usr/bin/env bash
set -Eeuo pipefail

readonly RELEASE_TAG="${RELEASE_TAG:-omarchy-arm64-v4.0.1-preview}"
readonly REPOSITORY="${REPOSITORY:-T-Py-T/talos-cluster-testing}"
readonly OUTPUT_DIR="${OUTPUT_DIR:-${PWD}/omarchy-arm64-release}"
readonly RELEASE_BASE="https://github.com/${REPOSITORY}/releases/download/${RELEASE_TAG}"
readonly ISO_NAME='omarchy-4.0.1-aarch64.iso'

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

download() {
  local name=$1
  curl \
    --fail \
    --location \
    --retry 5 \
    --retry-all-errors \
    --show-error \
    --output "${OUTPUT_DIR}/${name}" \
    "${RELEASE_BASE}/${name}"
}

main() {
  local part
  local -a parts=()

  mkdir -p "${OUTPUT_DIR}"

  log 'Downloading build status and checksum manifests.'
  download status.json
  download "${ISO_NAME}.sha256"
  download "${ISO_NAME}.parts.sha256"

  if ! command -v jq >/dev/null 2>&1; then
    printf 'jq is required. Install it with: brew install jq\n' >&2
    return 1
  fi

  jq -e '
    .bootstrap == "success" and
    .build == "success" and
    .validation == "success" and
    .split == "success"
  ' "${OUTPUT_DIR}/status.json" >/dev/null

  while read -r _ part; do
    [[ -n "${part}" ]] || continue
    parts+=("${part}")
    log "Downloading ${part}."
    download "${part}"
  done < "${OUTPUT_DIR}/${ISO_NAME}.parts.sha256"

  if [[ "${#parts[@]}" -eq 0 ]]; then
    printf 'No ISO parts were listed in the release manifest.\n' >&2
    return 1
  fi

  log 'Verifying every split part.'
  (
    cd "${OUTPUT_DIR}"
    shasum --algorithm 256 --check "${ISO_NAME}.parts.sha256"
  )

  log 'Reconstructing the ISO.'
  rm -f "${OUTPUT_DIR}/${ISO_NAME}"
  for part in "${parts[@]}"; do
    cat "${OUTPUT_DIR}/${part}" >> "${OUTPUT_DIR}/${ISO_NAME}"
  done

  log 'Verifying the complete ISO.'
  (
    cd "${OUTPUT_DIR}"
    shasum --algorithm 256 --check "${ISO_NAME}.sha256"
  )

  printf '\nVerified ISO:\n%s\n' "${OUTPUT_DIR}/${ISO_NAME}"
}

main "$@"
