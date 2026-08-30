#!/usr/bin/env python3
"""Patch the proven ARM ISO builder for the pinned Omarchy 4.0.1 fork."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_exact(path: Path, old: str, new: str, expected: int = 1) -> None:
    content = path.read_text(encoding="utf-8")
    actual = content.count(old)
    if actual != expected:
        raise RuntimeError(
            f"{path}: expected {expected} occurrence(s), found {actual}: {old!r}"
        )
    path.write_text(content.replace(old, new), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--builder", type=Path, required=True)
    parser.add_argument("--release-url", required=True)
    parser.add_argument("--fingerprint", required=True)
    parser.add_argument("--omarchy-ref", required=True)
    args = parser.parse_args()

    builder = args.builder.resolve()
    build_script = builder / "builder/build-iso.sh"
    make_script = builder / "bin/omarchy-iso-make"
    stable_pacman = builder / "configs/pacman-online-stable.conf"
    test_script = builder / "bin/omarchy-iso-test"

    replace_exact(
        build_script,
        "40DFB630FF42BCFFB047046CF0134EE680CAC571",
        args.fingerprint,
    )
    replace_exact(
        stable_pacman,
        "https://pkgs.omarchy.org/stable/$arch",
        args.release_url,
    )
    replace_exact(
        make_script,
        "    OMARCHY_MIRROR=edge\n    OMARCHY_ISO_REF=local\n",
        f"    OMARCHY_MIRROR=stable\n    OMARCHY_ISO_REF={args.omarchy_ref}\n",
    )
    replace_exact(
        make_script,
        'docker run "${DOCKER_ARGS[@]}" archlinux/archlinux:latest /$BUILD_SCRIPT\n',
        '# Build natively on the host architecture. The official Arch Linux\n'
        '# container publishes only AMD64, so ARM uses Arch Linux ARM.\n'
        'case "$(uname -m)" in\n'
        '  aarch64|arm64) BUILD_IMAGE=menci/archlinuxarm:base-devel ;;\n'
        '  *) BUILD_IMAGE=archlinux/archlinux:latest ;;\n'
        'esac\n\n'
        'docker run "${DOCKER_ARGS[@]}" "$BUILD_IMAGE" /$BUILD_SCRIPT\n',
    )

    # The upstream test harness is complete, but its VM launcher is x86_64-only.
    # Keep its real OCR-driven installer flow and replace only host dependencies,
    # firmware paths, machine devices, and the IDE CD-ROM attachment.
    replace_exact(
        test_script,
        "omarchy-pkg-add qemu-full edk2-ovmf socat imagemagick tesseract tesseract-data-eng\n",
        "command -v qemu-system-aarch64 >/dev/null\n"
        "command -v qemu-img >/dev/null\n"
        "command -v socat >/dev/null\n"
        "command -v tesseract >/dev/null\n"
        "command -v magick >/dev/null\n",
    )
    replace_exact(
        test_script,
        'OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"\n'
        'OVMF_VARS_TEMPLATE="/usr/share/edk2/x64/OVMF_VARS.4m.fd"\n',
        'OVMF_CODE="${AAVMF_CODE:-/usr/share/AAVMF/AAVMF_CODE.fd}"\n'
        'OVMF_VARS_TEMPLATE="${AAVMF_VARS:-/usr/share/AAVMF/AAVMF_VARS.fd}"\n'
        '[[ -f $OVMF_CODE ]] || { echo "AArch64 UEFI code firmware not found: $OVMF_CODE" >&2; exit 1; }\n'
        '[[ -f $OVMF_VARS_TEMPLATE ]] || { echo "AArch64 UEFI vars firmware not found: $OVMF_VARS_TEMPLATE" >&2; exit 1; }\n'
        "if [[ -r /dev/kvm && -w /dev/kvm ]]; then\n"
        "  QEMU_ACCEL_ARGS=(-machine virt,gic-version=3,accel=kvm -cpu host)\n"
        "else\n"
        "  QEMU_ACCEL_ARGS=(-machine virt,gic-version=3,accel=tcg -cpu max)\n"
        "fi\n",
    )
    replace_exact(
        test_script,
        "  qemu-system-x86_64 \\\n"
        "    -cpu host -enable-kvm -machine q35,accel=kvm \\\n"
        "    -smp \"$(nproc)\" \\\n"
        "    -m \"$MEMORY\" \\\n"
        "    -drive if=pflash,format=raw,readonly=on,file=\"$OVMF_CODE\" \\\n"
        "    -drive if=pflash,format=raw,file=\"$BASE_OVMF\" \\\n"
        "    -drive file=\"$disk\",format=qcow2,if=none,id=drive0 \\\n"
        "    -device virtio-blk-pci,drive=drive0,bootindex=1 \\\n"
        "    -device virtio-vga \\\n"
        "    -display none \\\n"
        "    -usb -device usb-tablet \\\n",
        "  qemu-system-aarch64 \\\n"
        "    \"${QEMU_ACCEL_ARGS[@]}\" \\\n"
        "    -smp \"$(nproc)\" \\\n"
        "    -m \"$MEMORY\" \\\n"
        "    -drive if=pflash,format=raw,readonly=on,file=\"$OVMF_CODE\" \\\n"
        "    -drive if=pflash,format=raw,file=\"$BASE_OVMF\" \\\n"
        "    -drive file=\"$disk\",format=qcow2,if=none,id=drive0 \\\n"
        "    -device virtio-blk-pci,drive=drive0,bootindex=1 \\\n"
        "    -device virtio-gpu-pci \\\n"
        "    -display none \\\n"
        "    -device qemu-xhci -device usb-tablet \\\n",
    )
    replace_exact(
        test_script,
        "    -device ide-cd,drive=cdrom0,bootindex=2\n",
        "    -device virtio-scsi-pci,id=scsi0 \\\n"
        "    -device scsi-cd,drive=cdrom0,bootindex=2\n",
    )
    replace_exact(
        test_script,
        '  ssh_guest "echo $GUEST_PASSWORD | sudo -S cat /var/log/pacman.log 2>/dev/null" \\\n'
        '    >"$RUN_DIR/pacman.log" 2>/dev/null || true\n\n'
        '  log "Installed system is up. Saving base image."\n',
        '  ssh_guest "echo $GUEST_PASSWORD | sudo -S cat /var/log/pacman.log 2>/dev/null" \\\n'
        '    >"$RUN_DIR/pacman.log" 2>/dev/null || true\n'
        '  ssh_guest "uname -a; echo; pacman -Q omarchy omarchy-settings; echo; '
        'systemctl --failed --no-legend || true" \\\n'
        '    >"$RUN_DIR/installed-system.txt" 2>/dev/null || true\n\n'
        '  log "Installed system is up. Saving base image."\n',
    )

    print(f"Patched builder at {builder}")


if __name__ == "__main__":
    main()
