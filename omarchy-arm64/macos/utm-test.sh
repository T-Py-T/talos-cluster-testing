#!/usr/bin/env bash
set -Eeuo pipefail

readonly DEFAULT_UTMCTL='/Applications/UTM.app/Contents/MacOS/utmctl'
readonly REPORT_ROOT_DEFAULT="${PWD}/omarchy-utm-report-$(date -u +'%Y%m%dT%H%M%SZ')"

ISO_PATH=''
VM_ID=''
REPORT_ROOT="${REPORT_ROOT_DEFAULT}"
START_VM='false'
ALLOW_ANY_VM='false'

usage() {
  cat <<'USAGE'
Usage:
  bash utm-test.sh --iso {{ ISO_PATH }} [options]

Options:
  --vm-id {{ UTM_VM_ID }}   Existing disposable UTM VM UUID to start.
  --start                   Start the selected VM after validation.
  --allow-any-vm            Disable the disposable-name safety check.
  --report-dir {{ PATH }}   Report output directory.
  --help                    Show this help.

This script does not create, modify, install, stop, or delete a VM. It validates
all prerequisites, records the UTM inventory, and optionally starts an existing
disposable test VM. Follow UTM_TEST_PLAN.md to create that VM safely.
USAGE
}

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "${REPORT_ROOT}/run.log"
}

parse_arguments() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --iso)
        ISO_PATH="${2:?Missing value for --iso}"
        shift 2
        ;;
      --vm-id)
        VM_ID="${2:?Missing value for --vm-id}"
        shift 2
        ;;
      --report-dir)
        REPORT_ROOT="${2:?Missing value for --report-dir}"
        shift 2
        ;;
      --start)
        START_VM='true'
        shift
        ;;
      --allow-any-vm)
        ALLOW_ANY_VM='true'
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done
}

resolve_utmctl() {
  if [[ -x "${UTMCTL:-}" ]]; then
    printf '%s\n' "${UTMCTL}"
    return
  fi

  if [[ -x "${DEFAULT_UTMCTL}" ]]; then
    printf '%s\n' "${DEFAULT_UTMCTL}"
    return
  fi

  if command -v utmctl >/dev/null 2>&1; then
    command -v utmctl
    return
  fi

  return 1
}

verify_iso() {
  local checksum_file="${ISO_PATH}.sha256"
  local expected_name

  [[ -f "${ISO_PATH}" ]] || {
    printf 'ISO not found: %s\n' "${ISO_PATH}" >&2
    return 1
  }

  file "${ISO_PATH}" | tee "${REPORT_ROOT}/iso-file.txt"
  shasum --algorithm 256 "${ISO_PATH}" | tee "${REPORT_ROOT}/iso-sha256.txt"

  if [[ -f "${checksum_file}" ]]; then
    expected_name="$(awk '{print $2}' "${checksum_file}")"
    if [[ "${expected_name}" == "$(basename "${ISO_PATH}")" ]]; then
      (
        cd "$(dirname "${ISO_PATH}")"
        shasum --algorithm 256 --check "$(basename "${checksum_file}")"
      ) | tee "${REPORT_ROOT}/iso-checksum-validation.txt"
    else
      log "Checksum file exists but names ${expected_name}; recording rather than applying it to a different filename."
    fi
  else
    log 'No adjacent checksum manifest was found; the calculated checksum was recorded.'
  fi
}

record_utm_inventory() {
  local utmctl=$1

  "${utmctl}" --help > "${REPORT_ROOT}/utmctl-help.txt" 2>&1 || true
  "${utmctl}" list > "${REPORT_ROOT}/utm-inventory.txt" 2>&1
  "${utmctl}" version > "${REPORT_ROOT}/utm-version.txt" 2>&1 || true
}

find_vm_inventory_line() {
  local inventory=$1

  grep -F "${VM_ID}" "${inventory}" | head -n 1
}

validate_disposable_vm() {
  local inventory=$1
  local vm_line

  [[ -n "${VM_ID}" ]] || {
    printf 'A VM UUID is required with --start.\n' >&2
    return 1
  }

  vm_line="$(find_vm_inventory_line "${inventory}")"
  [[ -n "${vm_line}" ]] || {
    printf 'VM UUID was not found in the UTM inventory: %s\n' "${VM_ID}" >&2
    return 1
  }

  printf '%s\n' "${vm_line}" > "${REPORT_ROOT}/selected-vm.txt"

  if [[ "${ALLOW_ANY_VM}" != true ]] && ! grep -Eqi 'omarchy.*test|test.*omarchy|disposable' <<< "${vm_line}"; then
    printf 'Safety stop: selected VM does not look disposable: %s\n' "${vm_line}" >&2
    printf 'Rename it to include Omarchy and Test, or explicitly pass --allow-any-vm.\n' >&2
    return 1
  fi
}

start_vm() {
  local utmctl=$1
  local status_output

  validate_disposable_vm "${REPORT_ROOT}/utm-inventory.txt"
  log "Starting disposable UTM VM ${VM_ID}."
  "${utmctl}" start "${VM_ID}" > "${REPORT_ROOT}/utm-start.txt" 2>&1

  for _ in $(seq 1 30); do
    status_output="$("${utmctl}" status "${VM_ID}" 2>&1 || true)"
    printf '%s\n' "${status_output}" > "${REPORT_ROOT}/utm-status.txt"
    if grep -Eqi 'started|running' <<< "${status_output}"; then
      log 'UTM reports that the VM is running.'
      return
    fi
    sleep 2
  done

  printf 'UTM did not report a running state within 60 seconds.\n' >&2
  return 1
}

main() {
  local utmctl

  parse_arguments "$@"
  [[ -n "${ISO_PATH}" ]] || {
    usage >&2
    return 2
  }

  ISO_PATH="$(cd "$(dirname "${ISO_PATH}")" && pwd)/$(basename "${ISO_PATH}")"
  mkdir -p "${REPORT_ROOT}"

  log 'Validating the ARM64 ISO.'
  verify_iso

  utmctl="$(resolve_utmctl)" || {
    printf 'UTM CLI was not found. Install UTM in /Applications or set UTMCTL.\n' >&2
    return 1
  }
  printf '%s\n' "${utmctl}" > "${REPORT_ROOT}/utmctl-path.txt"

  log 'Recording UTM version, help, and VM inventory.'
  record_utm_inventory "${utmctl}"

  if [[ "${START_VM}" == true ]]; then
    start_vm "${utmctl}"
  else
    log 'Preflight passed. No VM was started because --start was not supplied.'
  fi

  printf 'PASS\n' > "${REPORT_ROOT}/result.txt"
  printf '\nReport directory:\n%s\n' "${REPORT_ROOT}"
}

main "$@"
