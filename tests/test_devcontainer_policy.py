"""Validate devcontainer wiring without mutating workspace config."""

import json
import re
from pathlib import Path

import pytest

TALOS_VERSION = "v1.7.4"


@pytest.fixture(scope="session")
def devcontainer(repo_root: Path) -> dict:
    path = repo_root / ".devcontainer" / "devcontainer.json"
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def test_devcontainer_json_is_valid(devcontainer: dict) -> None:
    assert devcontainer.get("name")
    assert devcontainer.get("postCreateCommand") == "bash .devcontainer/setup.sh"


def test_devcontainer_includes_cluster_tooling(devcontainer: dict) -> None:
    features = devcontainer.get("features") or {}
    assert "ghcr.io/devcontainers/features/docker-in-docker:2" in features
    assert "ghcr.io/devcontainers/features/kubectl-helm-minikube:1" in features


def test_setup_script_pins_talos_and_supports_architectures(repo_root: Path) -> None:
    setup = (repo_root / ".devcontainer" / "setup.sh").read_text(encoding="utf-8")
    assert f'TALOS_VERSION="{TALOS_VERSION}"' in setup
    assert 'x86_64)' in setup and 'ARCH="amd64"' in setup
    assert "aarch64|arm64)" in setup and 'ARCH="arm64"' in setup
    assert "set -e" in setup


def test_setup_script_download_url_uses_version_variable(repo_root: Path) -> None:
    setup = (repo_root / ".devcontainer" / "setup.sh").read_text(encoding="utf-8")
    assert re.search(
        r"talos/releases/download/\$\{TALOS_VERSION\}/talosctl-linux-\$\{ARCH\}",
        setup,
    ), "talosctl download URL must interpolate TALOS_VERSION and ARCH"
