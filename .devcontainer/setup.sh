#!/bin/bash
# .devcontainer/setup.sh
# Setup script for Talos cluster testing environment

set -e

echo "[INFO] Setting up Talos cluster testing environment..."

# Determine architecture
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo "[ERROR] Unsupported architecture: ${ARCH}"
        exit 1
        ;;
esac

echo "[INFO] Detected architecture: ${ARCH}"

# Install talosctl
echo "[INFO] Installing talosctl..."
TALOS_VERSION="v1.7.4"
TALOSCTL_TMP="$(mktemp)"
trap 'rm -f "${TALOSCTL_TMP}"' EXIT

curl -fsSL "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-${ARCH}" -o "${TALOSCTL_TMP}"

# curl -f rejects HTTP errors, but still guard against empty bodies or HTML error pages.
if [[ ! -s "${TALOSCTL_TMP}" ]]; then
    echo "[ERROR] talosctl download is empty" >&2
    exit 1
fi
if head -c 5 "${TALOSCTL_TMP}" | grep -qE '^<[a-zA-Z]'; then
    echo "[ERROR] talosctl download looks like HTML, not a release binary" >&2
    exit 1
fi

sudo install -m 755 "${TALOSCTL_TMP}" /usr/local/bin/talosctl

# Verify installations
echo "[INFO] Verifying installations..."
if ! talosctl version --client >/dev/null 2>&1; then
    echo "[ERROR] talosctl client failed verification after install" >&2
    exit 1
fi
kubectl version --client || echo "[WARN] kubectl not properly installed"
docker --version || echo "[WARN] docker not properly installed"
docker compose version || echo "[WARN] docker compose not properly installed"

echo "[INFO] Talos cluster testing environment is ready!"
echo "[INFO] Use 'docker compose up -d' to start the Talos cluster."
echo "[INFO] Use 'talosctl' to interact with the cluster."

