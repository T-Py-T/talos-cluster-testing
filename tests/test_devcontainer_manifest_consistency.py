"""Regression: devcontainer.json feature wiring and editor defaults."""

import json
from pathlib import Path

import pytest

REQUIRED_FEATURES = (
    "ghcr.io/devcontainers/features/git:1",
    "ghcr.io/devcontainers/features/github-cli:1",
    "ghcr.io/devcontainers/features/docker-in-docker:2",
    "ghcr.io/devcontainers/features/kubectl-helm-minikube:1",
)


@pytest.fixture(scope="module")
def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def devcontainer(repo_root: Path) -> dict:
    path = repo_root / ".devcontainer" / "devcontainer.json"
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def test_devcontainer_declares_cluster_lab_feature_bundle(devcontainer: dict) -> None:
    features = devcontainer.get("features") or {}
    for feature_id in REQUIRED_FEATURES:
        assert feature_id in features, f"missing devcontainer feature {feature_id}"


def test_devcontainer_json_has_no_duplicate_feature_keys(devcontainer: dict) -> None:
    raw = json.dumps(devcontainer.get("features") or {}, sort_keys=True)
    parsed = json.loads(raw)
    assert len(parsed) == len(devcontainer.get("features") or {})


def test_vscode_defaults_to_bash_terminal(devcontainer: dict) -> None:
    settings = (
        (devcontainer.get("customizations") or {}).get("vscode", {}).get("settings") or {}
    )
    assert settings.get("terminal.integrated.defaultProfile.linux") == "bash"


def test_devcontainer_image_is_published_microsoft_base(devcontainer: dict) -> None:
    image = devcontainer.get("image") or ""
    assert image.startswith("mcr.microsoft.com/devcontainers/base:")


def test_post_create_command_targets_repo_relative_setup_script(devcontainer: dict) -> None:
    command = devcontainer.get("postCreateCommand") or ""
    assert command == "bash .devcontainer/setup.sh"
