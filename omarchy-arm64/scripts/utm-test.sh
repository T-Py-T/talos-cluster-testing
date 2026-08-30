#!/usr/bin/env bash
set -Eeuo pipefail

ISO_PATH="${1:?Usage: utm-test.sh <iso-path> [vm-name]}"
VM_NAME="${2:-Omarchy-4.0.1-ARM64-Test-$(date +%Y%m%d-%H%M%S)}"
DISK_GIB="${UTM_DISK_GIB:-64}"
MEMORY_MIB="${UTM_MEMORY_MIB:-8192}"
CPU_COUNT="${UTM_CPU_COUNT:-4}"

[[ $(uname -s) == Darwin ]] || {
  echo "This helper must run on macOS." >&2
  exit 1
}
[[ $(uname -m) == arm64 ]] || {
  echo "This helper requires Apple Silicon." >&2
  exit 1
}
[[ -s $ISO_PATH ]] || {
  echo "ISO not found: $ISO_PATH" >&2
  exit 1
}
command -v osascript >/dev/null || {
  echo "osascript is required." >&2
  exit 1
}
[[ -d /Applications/UTM.app ]] || {
  echo "UTM is not installed at /Applications/UTM.app." >&2
  exit 1
}
[[ $DISK_GIB =~ ^[0-9]+$ && $DISK_GIB -ge 40 ]] || {
  echo "UTM_DISK_GIB must be an integer of at least 40." >&2
  exit 1
}
[[ $MEMORY_MIB =~ ^[0-9]+$ && $MEMORY_MIB -ge 4096 ]] || {
  echo "UTM_MEMORY_MIB must be an integer of at least 4096." >&2
  exit 1
}
[[ $CPU_COUNT =~ ^[0-9]+$ && $CPU_COUNT -ge 2 ]] || {
  echo "UTM_CPU_COUNT must be an integer of at least 2." >&2
  exit 1
}

ISO_PATH="$(cd "$(dirname "$ISO_PATH")" && pwd)/$(basename "$ISO_PATH")"
DISK_MIB=$((DISK_GIB * 1024))

cat <<INFO
Creating and starting a new disposable UTM test VM:
  Name:   $VM_NAME
  CPUs:   $CPU_COUNT
  Memory: $MEMORY_MIB MiB
  Disk:   $DISK_GIB GiB
  ISO:    $ISO_PATH

The script refuses to reuse or delete an existing VM with this name.
macOS may ask for permission to let Terminal control UTM.
INFO

VM_ID="$(osascript - "$ISO_PATH" "$VM_NAME" "$MEMORY_MIB" "$CPU_COUNT" "$DISK_MIB" <<'APPLESCRIPT'
on run argv
  set isoPath to item 1 of argv
  set vmName to item 2 of argv
  set memoryMiB to (item 3 of argv) as integer
  set cpuCount to (item 4 of argv) as integer
  set diskMiB to (item 5 of argv) as integer
  set isoFile to POSIX file isoPath

  tell application "UTM"
    set matchingVMs to every virtual machine whose name is vmName
    if (count of matchingVMs) is greater than 0 then
      error "Refusing to overwrite existing UTM VM: " & vmName
    end if

    set vm to make new virtual machine with properties {backend:qemu, configuration:{name:vmName, architecture:"aarch64", memory:memoryMiB, cpu cores:cpuCount, hypervisor:true, uefi:true, drives:{{removable:true, source:isoFile}, {guest size:diskMiB}}, displays:{{hardware:"virtio-gpu-pci", dynamic resolution:true}}}}
    start vm
    return id of vm
  end tell
end run
APPLESCRIPT
)"

cat <<INFO
UTM VM started successfully.
  Name: $VM_NAME
  ID:   $VM_ID

After validation, remove only this disposable VM from UTM's UI. The script does
not delete VMs automatically because UTM deletion is immediate and destructive.
INFO
