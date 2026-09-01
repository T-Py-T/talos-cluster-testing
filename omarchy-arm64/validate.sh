#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ISO_PATH="${1:-${SCRIPT_DIR}/dist/omarchy-4.0.1-aarch64.iso}"
readonly REPORT_DIR="${REPORT_DIR:-${SCRIPT_DIR}/dist/validation}"
readonly EXTRACT_DIR="${REPORT_DIR}/iso-tree"

log() {
  printf '\n[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

find_firmware() {
  local candidate
  for candidate in \
    /usr/share/AAVMF/AAVMF_CODE.fd \
    /usr/share/AAVMF/AAVMF_CODE.ms.fd \
    /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
    /usr/share/edk2/aarch64/QEMU_EFI.fd; do
    if [[ -r "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

validate_file_and_checksum() {
  test -s "${ISO_PATH}"
  file "${ISO_PATH}" | tee "${REPORT_DIR}/file.txt"
  sha256sum "${ISO_PATH}" | tee "${REPORT_DIR}/sha256.txt"
  xorriso -indev "${ISO_PATH}" -report_el_torito as_mkisofs \
    > "${REPORT_DIR}/eltorito.txt" 2>&1
}

extract_iso() {
  rm -rf "${EXTRACT_DIR}"
  mkdir -p "${EXTRACT_DIR}"
  xorriso -osirrox on -indev "${ISO_PATH}" -extract / "${EXTRACT_DIR}" \
    > "${REPORT_DIR}/extract.log" 2>&1
  find "${EXTRACT_DIR}" -printf '%P\n' | sort > "${REPORT_DIR}/iso-files.txt"
}

validate_arm_boot_payload() {
  local evidence="${REPORT_DIR}/arm64-evidence.txt"
  local package_evidence="${REPORT_DIR}/package-evidence.txt"

  grep -Eai '(^|/)(bootaa64\.efi|limine_aa64\.efi|linux-aarch64)(/|$)|aarch64|aa64' \
    "${REPORT_DIR}/iso-files.txt" > "${evidence}"
  test -s "${evidence}"

  grep -R -a -h -E '(^|[[:space:]])(linux-aarch64|omarchy)([<=>[:space:]-]|$)' \
    "${EXTRACT_DIR}" 2>/dev/null | sort -u > "${package_evidence}" || true

  if grep -R -a -E '(^|[[:space:]])(linux-t2|intel-ucode|amd-ucode|syslinux)([<=>[:space:]-]|$)' \
    "${EXTRACT_DIR}" > "${REPORT_DIR}/x86-only-packages.txt" 2>/dev/null; then
    printf 'Unexpected x86-only package references were found.\n' >&2
    cat "${REPORT_DIR}/x86-only-packages.txt" >&2
    return 1
  fi
}

qemu_smoke_test() {
  local firmware
  local qemu_log="${REPORT_DIR}/qemu-uefi-smoke.log"
  local status=0

  firmware="$(find_firmware)"
  printf '%s\n' "${firmware}" > "${REPORT_DIR}/qemu-firmware.txt"

  set +e
  timeout --signal=TERM --kill-after=15s 120s \
    qemu-system-aarch64 \
      -machine virt,gic-version=3 \
      -cpu max \
      -smp 4 \
      -m 4096 \
      -bios "${firmware}" \
      -boot order=d \
      -cdrom "${ISO_PATH}" \
      -device virtio-gpu-pci \
      -display none \
      -serial file:"${qemu_log}" \
      -monitor none \
      -no-reboot \
      -no-shutdown
  status=$?
  set -e

  printf '%s\n' "${status}" > "${REPORT_DIR}/qemu-exit-code.txt"
  if [[ ${status} -ne 0 && ${status} -ne 124 ]]; then
    cat "${qemu_log}" >&2 || true
    return "${status}"
  fi

  if grep -Eqi 'Could not open|No bootable device|failed to load|unsupported machine|invalid ELF' "${qemu_log}"; then
    cat "${qemu_log}" >&2
    return 1
  fi
}

main() {
  rm -rf "${REPORT_DIR}"
  mkdir -p "${REPORT_DIR}"

  log 'Validating ISO structure and checksum.'
  validate_file_and_checksum

  log 'Extracting the ISO for architecture checks.'
  extract_iso

  log 'Validating ARM64 boot payload and package references.'
  validate_arm_boot_payload

  log 'Running a native AArch64 UEFI QEMU smoke test.'
  qemu_smoke_test

  date -u +'%Y-%m-%dT%H:%M:%SZ' > "${REPORT_DIR}/validated-at.txt"
  printf 'PASS\n' > "${REPORT_DIR}/result.txt"
}

main "$@"
