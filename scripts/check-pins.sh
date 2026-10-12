#!/usr/bin/env bash
# Ensure Talos and kubectl pins stay aligned with lab-versions.env.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/lab-versions.env"

if [[ -z "${TALOS_VERSION:-}" ]]; then
  echo "TALOS_VERSION is not set in lab-versions.env" >&2
  exit 1
fi

if [[ -z "${KUBECTL_VERSION:-}" ]]; then
  echo "KUBECTL_VERSION is not set in lab-versions.env" >&2
  exit 1
fi

if [[ ! "${TALOS_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
  echo "TALOS_VERSION must look like a Talos release tag (e.g. v1.14.2)" >&2
  exit 1
fi

expected_image="ghcr.io/siderolabs/talos:${TALOS_VERSION}"
anchor_line="x-talos-version: &talos_version ${TALOS_VERSION}"

if ! grep -qF "${anchor_line}" compose.yaml; then
  echo "compose.yaml anchor does not match lab-versions.env (${TALOS_VERSION})" >&2
  exit 1
fi

image_count="$(grep -cF "image: ghcr.io/siderolabs/talos:*talos_version" compose.yaml || true)"
if [[ "${image_count}" -ne 2 ]]; then
  echo "expected two Talos services using the compose anchor; found ${image_count}" >&2
  exit 1
fi

if ! grep -qF "releases/download/\${TALOS_VERSION}/" "${REPO_ROOT}/.devcontainer/setup.sh"; then
  echo "setup.sh does not install talosctl from lab-versions.env" >&2
  exit 1
fi

if ! grep -qF "\"version\": \"${KUBECTL_VERSION}\"" "${REPO_ROOT}/.devcontainer/devcontainer.json"; then
  echo "devcontainer.json kubectl feature version does not match KUBECTL_VERSION (${KUBECTL_VERSION})" >&2
  exit 1
fi

echo "Pin check OK: ${expected_image}, kubectl ${KUBECTL_VERSION}"
