#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

python3 -m pip install -q -r requirements-test.txt
python3 -m pytest -q tests/test_concrete_regressions.py
