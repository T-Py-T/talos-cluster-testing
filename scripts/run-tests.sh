#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v bats >/dev/null 2>&1; then
  echo "bats is required to run script tests (e.g. apt install bats)" >&2
  exit 1
fi

bats tests/bats
