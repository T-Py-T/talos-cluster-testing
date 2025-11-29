#!/bin/bash
# .devcontainer/setup.sh
# Setup script for Talos cluster testing environment

set -e

echo "[INFO] Setting up Talos cluster testing environment..."

# Determine architecture
ARCH=$(uname -m)
case ${ARCH} in
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
curl -sL https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-${ARCH} -o /tmp/talosctl
sudo install -m 755 /tmp/talosctl /usr/local/bin/talosctl
rm /tmp/talosctl

# Verify installations
echo "[INFO] Verifying installations..."
talosctl version --client || echo "[WARN] talosctl not properly installed"
kubectl version --client || echo "[WARN] kubectl not properly installed"
docker --version || echo "[WARN] docker not properly installed"
docker compose version || echo "[WARN] docker compose not properly installed"

echo "[INFO] Talos cluster testing environment is ready!"
echo "[INFO] Use 'docker compose up -d' to start the Talos cluster."
echo "[INFO] Use 'talosctl' to interact with the cluster."

