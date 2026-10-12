#!/usr/bin/env bash
# Structural checks for devcontainer, Compose, and Dependabot lab manifests.
set -euo pipefail

REPO_ROOT="${LAB_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "${REPO_ROOT}"

fail() {
  echo "validate-lab-manifests: $*" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "required command not found: $1"
  fi
}

require_cmd jq

devcontainer="${REPO_ROOT}/.devcontainer/devcontainer.json"
if [[ ! -f "${devcontainer}" ]]; then
  fail "missing ${devcontainer}"
fi

jq -e '.postCreateCommand | test("setup\\.sh")' "${devcontainer}" >/dev/null \
  || fail "devcontainer.json postCreateCommand must run setup.sh"

jq -e '.workspaceFolder | startswith("/workspaces/")' "${devcontainer}" >/dev/null \
  || fail "devcontainer.json workspaceFolder must use /workspaces/ (Codespaces/devcontainers convention)"

jq -e '.remoteUser == "vscode"' "${devcontainer}" >/dev/null \
  || fail "devcontainer.json remoteUser must be vscode for base image"

# shellcheck source=/dev/null
source "${REPO_ROOT}/lab-versions.env"
if [[ ! "${TALOS_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "TALOS_VERSION must look like vMAJOR.MINOR.PATCH (got: ${TALOS_VERSION})"
fi

for service in talos-cp talos-worker; do
  if ! grep -qE "^  ${service}:" "${REPO_ROOT}/compose.yaml"; then
    fail "compose.yaml missing service ${service}"
  fi
done

if ! grep -qF 'PLATFORM=container' "${REPO_ROOT}/compose.yaml"; then
  fail "compose.yaml must set PLATFORM=container for Talos container mode"
fi

platform_count="$(grep -cF 'PLATFORM=container' "${REPO_ROOT}/compose.yaml" || true)"
if [[ "${platform_count}" -ne 2 ]]; then
  fail "expected PLATFORM=container on both Talos services; found ${platform_count}"
fi

dependabot="${REPO_ROOT}/.github/dependabot.yml"
if [[ ! -f "${dependabot}" ]]; then
  fail "missing ${dependabot}"
fi

for ecosystem in github-actions docker-compose; do
  if ! grep -qF "package-ecosystem: ${ecosystem}" "${dependabot}"; then
    fail "dependabot.yml should track ${ecosystem}"
  fi
done

if command -v docker >/dev/null 2>&1; then
  rendered="$(docker compose -f "${REPO_ROOT}/compose.yaml" config 2>&1)" || fail "docker compose config failed: ${rendered}"
  if [[ "$(grep -cF 'PLATFORM=container' <<<"${rendered}")" -lt 2 ]]; then
    fail "rendered compose config missing PLATFORM=container on both services"
  fi
  for service in talos-cp talos-worker; do
    if ! grep -qF "${service}:" <<<"${rendered}"; then
      fail "rendered compose config missing service ${service}"
    fi
  done
else
  echo "validate-lab-manifests: skipping docker compose render (docker not installed)" >&2
fi

echo "Lab manifest validation OK"
