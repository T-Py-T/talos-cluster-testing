#!/usr/bin/env bash
set -Eeuo pipefail

BUILDER_DIR="${1:?Usage: qemu-install-test.sh <builder-directory> <iso-path> [report-directory]}"
ISO_PATH="${2:?Usage: qemu-install-test.sh <builder-directory> <iso-path> [report-directory]}"
REPORT_DIR="${3:-$(dirname "$ISO_PATH")/qemu-install}"
mkdir -p "$REPORT_DIR"

find_firmware() {
  local kind="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if [[ -f $candidate ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "Unable to find AArch64 UEFI $kind firmware." >&2
  return 1
}

AAVMF_CODE="$(find_firmware code \
  /usr/share/AAVMF/AAVMF_CODE.fd \
  /usr/share/AAVMF/AAVMF_CODE.ms.fd \
  /usr/share/qemu-efi-aarch64/QEMU_EFI.fd)"
AAVMF_VARS="$(find_firmware vars \
  /usr/share/AAVMF/AAVMF_VARS.fd \
  /usr/share/AAVMF/AAVMF_VARS.ms.fd)"
export AAVMF_CODE AAVMF_VARS

if ! command -v magick >/dev/null && command -v convert >/dev/null; then
  mkdir -p "$REPORT_DIR/bin"
  ln -sf "$(command -v convert)" "$REPORT_DIR/bin/magick"
  export PATH="$REPORT_DIR/bin:$PATH"
fi
command -v magick >/dev/null || {
  echo "ImageMagick's magick or convert command is required." >&2
  exit 1
}

TEST_ROOT="$BUILDER_DIR/test-runs"
rm -rf "$TEST_ROOT"

# This invokes the builder's real OCR/QMP acceptance harness. --install-only
# still performs a complete installation, reboots the installed disk, logs in
# on a TTY, enables SSH, verifies SSH connectivity, and captures guest facts.
"$BUILDER_DIR/bin/omarchy-iso-test" "$ISO_PATH" \
  --install-only \
  --no-preview \
  --memory 8192 \
  --timeout 5400

LATEST_RUN="$(find "$TEST_ROOT" -type d -path '*/runs/*' -print | sort | tail -1)"
[[ -n $LATEST_RUN ]] || {
  echo "QEMU test completed without a run directory." >&2
  exit 1
}
[[ -s $LATEST_RUN/installed-system.txt ]] || {
  echo "Installed guest facts were not collected." >&2
  exit 1
}
grep -Eq '^Linux .* aarch64 ' "$LATEST_RUN/installed-system.txt" || {
  echo "Installed guest did not report an AArch64 kernel." >&2
  cat "$LATEST_RUN/installed-system.txt" >&2
  exit 1
}
grep -Eq '^omarchy 4\.0\.1([.-]|$)' "$LATEST_RUN/installed-system.txt" || {
  echo "Installed guest did not report Omarchy 4.0.1." >&2
  cat "$LATEST_RUN/installed-system.txt" >&2
  exit 1
}

cp -a "$LATEST_RUN/." "$REPORT_DIR/"
find "$REPORT_DIR" -type f -name '*.qcow2' -delete
find "$REPORT_DIR" -type f -name '*.fd' -delete
find "$REPORT_DIR" -type f -name 'id_ed25519*' -delete

cat "$REPORT_DIR/installed-system.txt"
