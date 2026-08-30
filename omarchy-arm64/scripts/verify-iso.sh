#!/usr/bin/env bash
set -Eeuo pipefail

ISO_PATH="${1:?Usage: verify-iso.sh <iso-path> [report-directory]}"
REPORT_DIR="${2:-$(dirname "$ISO_PATH")/verification}"
mkdir -p "$REPORT_DIR"

fail() {
  echo "ISO verification failed: $*" >&2
  exit 1
}

[[ -s $ISO_PATH ]] || fail "ISO is missing or empty: $ISO_PATH"
[[ $(uname -m) == aarch64 ]] || fail "verification host must be AArch64"

xorriso -indev "$ISO_PATH" -find / -type f -print 2>/dev/null \
  | sed -n 's/^xorriso : UPDATE : //p; /^\//p' \
  | sort -u >"$REPORT_DIR/iso-files.txt"

require_path() {
  local pattern="$1" description="$2"
  grep -Eiq "$pattern" "$REPORT_DIR/iso-files.txt" || fail "$description"
}
reject_path() {
  local pattern="$1" description="$2"
  if grep -Eiq "$pattern" "$REPORT_DIR/iso-files.txt"; then
    grep -Ei "$pattern" "$REPORT_DIR/iso-files.txt" >&2 || true
    fail "$description"
  fi
}

require_path '/EFI/BOOT/BOOTAA64\.EFI$' "missing removable-media ARM64 UEFI loader"
require_path '/arch/boot/aarch64/vmlinuz-linux-aarch64$' "missing linux-aarch64 kernel"
require_path '/arch/boot/aarch64/initramfs-linux-aarch64\.img$' "missing ARM64 initramfs"
require_path '/arch/aarch64/airootfs\.sfs$' "missing AArch64 live root filesystem"
reject_path 'vmlinuz-linux-t2|BOOTX64\.EFI|syslinux' "x86-only boot files are present"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
SFS="$TMP_DIR/airootfs.sfs"
xorriso -osirrox on -indev "$ISO_PATH" \
  -extract /arch/aarch64/airootfs.sfs "$SFS" >/dev/null 2>&1
[[ -s $SFS ]] || fail "could not extract airootfs.sfs"

unsquashfs -ll "$SFS" >"$REPORT_DIR/airootfs-files.txt"
for required in \
  root/omarchy_iso_ref \
  usr/share/omarchy-iso/build-info \
  usr/share/omarchy-iso/package-targets; do
  grep -Fq "squashfs-root/$required" "$REPORT_DIR/airootfs-files.txt" \
    || fail "live root is missing $required"
done

ISO_REF="$(unsquashfs -cat "$SFS" root/omarchy_iso_ref 2>/dev/null | tr -d '\r\n')"
[[ $ISO_REF == v4.0.1-aarch64.2 ]] || fail "unexpected bundled ref: $ISO_REF"
unsquashfs -cat "$SFS" usr/share/omarchy-iso/build-info \
  >"$REPORT_DIR/build-info.txt" 2>/dev/null
unsquashfs -cat "$SFS" usr/share/omarchy-iso/package-targets \
  >"$REPORT_DIR/package-targets.txt" 2>/dev/null
grep -Fxq 'OMARCHY_RUNTIME_PACKAGE=omarchy' "$REPORT_DIR/package-targets.txt" \
  || fail "runtime package is not the stable omarchy package"
grep -Fxq 'OMARCHY_SETTINGS_PACKAGE=omarchy-settings' "$REPORT_DIR/package-targets.txt" \
  || fail "settings package is not the stable package"

PKG_RELATIVE="$(awk '$NF ~ /\/var\/cache\/omarchy\/mirror\/offline\/omarchy-[^/]+\.pkg\.tar\.(zst|xz)$/ {sub(/^squashfs-root\//, "", $NF); print $NF; exit}' "$REPORT_DIR/airootfs-files.txt")"
[[ -n $PKG_RELATIVE ]] || fail "bundled omarchy package was not found"
unsquashfs -f -d "$TMP_DIR/root" "$SFS" "$PKG_RELATIVE" >/dev/null
PKG_FILE="$TMP_DIR/root/$PKG_RELATIVE"
bsdtar -xOf "$PKG_FILE" .PKGINFO >"$REPORT_DIR/omarchy.PKGINFO"
grep -Fxq 'pkgname = omarchy' "$REPORT_DIR/omarchy.PKGINFO" \
  || fail "bundled package is not omarchy"
grep -Eq '^pkgver = 4\.0\.1([.-]|$)' "$REPORT_DIR/omarchy.PKGINFO" \
  || fail "bundled Omarchy package is not based on 4.0.1"

if grep -Eiq '(^|/)(linux-t2|intel-ucode|amd-ucode|syslinux|refind)-[^/]*\.pkg\.tar\.' \
  "$REPORT_DIR/airootfs-files.txt"; then
  grep -Ei '(^|/)(linux-t2|intel-ucode|amd-ucode|syslinux|refind)-[^/]*\.pkg\.tar\.' \
    "$REPORT_DIR/airootfs-files.txt" >&2 || true
  fail "x86-only packages are bundled in the offline mirror"
fi

{
  echo "iso=$(basename "$ISO_PATH")"
  echo "sha256=$(sha256sum "$ISO_PATH" | awk '{print $1}')"
  echo "size_bytes=$(stat -c %s "$ISO_PATH")"
  echo "architecture=aarch64"
  echo "omarchy_ref=$ISO_REF"
  grep -E '^(pkgname|pkgver) = ' "$REPORT_DIR/omarchy.PKGINFO"
} >"$REPORT_DIR/summary.txt"

cat "$REPORT_DIR/summary.txt"
