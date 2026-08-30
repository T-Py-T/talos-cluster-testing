#!/usr/bin/env bash
set -euo pipefail
cat omarchy-arm64-factory.tar.gz.b64.part-* | base64 --decode | tar -xzf -
