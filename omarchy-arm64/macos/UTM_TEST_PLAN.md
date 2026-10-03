# Omarchy 4.0.1 ARM64 UTM Test Plan

The CI workflow already performs a native AArch64 UEFI QEMU boot smoke test. This plan covers the final Apple Silicon and UTM-specific installation test without modifying an existing VM.

## 1. Download and verify the ISO

From the repository root on the Mac:

```bash
bash omarchy-arm64/macos/download-release.sh
```

Expected result:

- `status.json` reports `success` for bootstrap, build, validation, and split.
- Every split part passes SHA-256 verification.
- The reconstructed `omarchy-4.0.1-aarch64.iso` passes the complete SHA-256 verification.

## 2. Create a disposable UTM VM

Create a new VM named `Omarchy ARM64 Test - Disposable`. Do not reuse an existing development or production VM.

Use these settings:

| Setting | Value |
| --- | --- |
| Virtualization | Virtualize |
| Operating system | Linux |
| Architecture | ARM64 / aarch64 |
| Boot | UEFI |
| CPU | 4 or more cores |
| Memory | 8192 MB recommended; 4096 MB minimum |
| Storage | 64 GB minimum |
| Removable drive | `omarchy-4.0.1-aarch64.iso` |
| Network | Shared Network |
| Display | VirtIO-GPU / default Linux display |
| Clipboard and directory sharing | Disabled for the first boot test |

Take a UTM snapshot named `blank-disk-before-install` after the VM configuration is saved and before starting the installer.

## 3. Record the UTM preflight

Find the VM UUID in UTM or from:

```bash
/Applications/UTM.app/Contents/MacOS/utmctl list
```

Run the non-destructive preflight:

```bash
bash omarchy-arm64/macos/utm-test.sh \
  --iso "{{ ISO_PATH }}" \
  --vm-id "{{ UTM_VM_ID }}"
```

The script verifies the ISO, records the UTM version and VM inventory, and does not start or modify the VM.

To start the disposable VM after the preflight:

```bash
bash omarchy-arm64/macos/utm-test.sh \
  --iso "{{ ISO_PATH }}" \
  --vm-id "{{ UTM_VM_ID }}" \
  --start
```

## 4. Live ISO checks

The live environment passes when all of the following are true:

1. UEFI loads the ISO without a no-boot-device message.
2. The ARM64 kernel starts without an invalid executable or architecture error.
3. The installer UI or shell becomes usable.
4. The virtual disk and shared network adapter are visible.
5. The display remains responsive for at least five minutes.

Record screenshots of the boot menu, installer start, detected disk, and network state.

## 5. Installation checks

Install only to the disposable 64 GB virtual disk. The installation passes when:

1. Partitioning completes without selecting the ISO drive.
2. Package installation completes without x86-only package errors.
3. The bootloader installs an ARM64 UEFI target.
4. The installer reaches its successful completion state.

Before rebooting, eject the ISO from the UTM removable drive.

## 6. Installed-system checks

After rebooting from the virtual disk, collect:

```bash
uname -a
uname -m
cat /etc/os-release
pacman -Q omarchy 2>/dev/null || true
systemctl --failed --no-pager
ip address
ip route
```

Expected results:

- `uname -m` is `aarch64`.
- The system boots from the virtual disk through UEFI.
- No x86-only kernel or microcode package is required.
- The desktop or expected Omarchy session starts.
- Shared networking provides an address and default route.
- Failed systemd units are either empty or documented with a specific cause.

## 7. Result bundle

Keep the generated `omarchy-utm-report-*` directory together with:

- UTM version.
- VM UUID and configuration screenshots.
- ISO and checksum manifests.
- Live boot screenshots.
- Installer completion screenshot.
- Installed-system command output.

Do not delete the disposable VM until the report has been reviewed. Revert to `blank-disk-before-install` for any repeat test.
