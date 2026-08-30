# Omarchy 4.0.1 AArch64 ISO

This branch builds an offline Omarchy 4.0.1 installer ISO on a native GitHub-hosted ARM64 runner. It uses the generic AArch64 ISO work from `oceanapplications/omarchy-iso`, the stable `v4.0.1-aarch64.2` source fork, and the matching signed AArch64 package recipes.

## Validation performed in CI

1. Verify every source checkout and release identifier before building.
2. Verify the package-signing key by SHA-256 and full fingerprint.
3. Build Omarchy packages from the pinned source checkout.
4. Build the offline ARM64 ISO.
5. Inspect its UEFI loader, kernel, initramfs, squashfs, package targets, and bundled Omarchy package metadata.
6. Boot the ISO under native AArch64 QEMU using UEFI.
7. Drive the real installer through screenshots, OCR, and QMP keyboard events.
8. Reboot the installed disk, log in through its console, enable SSH, and collect architecture, package, and failed-unit information.

The build artifacts include the ISO, checksums, source manifest, builder patch, verification report, installer screenshots, and guest logs. The 40 GiB test disk and generated SSH credentials are intentionally excluded.

## Run the workflow

Push to the `omarchy-arm64-iso` branch or launch **Build Omarchy 4.0.1 ARM64 ISO** from GitHub Actions.

## Final UTM check

After downloading the ISO on an Apple Silicon Mac:

```bash
chmod +x omarchy-arm64/scripts/utm-test.sh
./omarchy-arm64/scripts/utm-test.sh ./omarchy-4.0.1-aarch64.iso
```

The helper uses UTM's AppleScript bridge to create and start a new QEMU ARM64 VM. It refuses to reuse or delete an existing VM with the same name.
