# Omarchy 4.0.1 ARM64 ISO factory

This branch runs the pinned Omarchy ARM64 factory release `r3`.

The repository payload is stored as `omarchy-arm64-factory.tar.gz.b64` because the connected GitHub integration can create UTF-8 files but cannot upload binary archives or an atomic multi-file tree. Each native ARM job expands that payload before running the same validated scripts contained in the downloadable factory ZIP.

The workflow performs four gates:

1. Build the signed-input-aware AArch64 Omarchy package closure from the pinned package-builder commit.
2. Build a generic UEFI AArch64 ISO with the exact Omarchy `v4.0.1` source plus reviewed ARM patches.
3. Install the ISO unattended in native ARM QEMU and verify the bootloader, desktop, package repository, upgrade path, guest agent, and UTM integration package.
4. Publish the package repository to release `omarchy-arm64-v4.0.1-r3` and retain the ISO as a workflow artifact.

The final UTM acceptance script is inside the payload at `omarchy-arm64/scripts/run-utm-acceptance.command`.
