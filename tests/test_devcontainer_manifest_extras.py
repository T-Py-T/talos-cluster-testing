"""Devcontainer manifest and Dockerfile policy beyond postCreate/setup.sh checks."""

import json
import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
TALOS_VERSION = "v1.7.4"
EXPECTED_EXTENSIONS = (
    "ms-kubernetes-tools.vscode-kubernetes-tools",
    "redhat.vscode-yaml",
    "ms-vscode.vscode-json",
    "ms-azuretools.vscode-docker",
)


@pytest.fixture(scope="module")
def repo_root() -> Path:
    return REPO_ROOT


@pytest.fixture(scope="module")
def devcontainer(repo_root: Path) -> dict:
    path = repo_root / ".devcontainer" / "devcontainer.json"
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def test_remote_user_and_workspace_folder(devcontainer: dict) -> None:
    assert devcontainer.get("remoteUser") == "vscode"
    folder = devcontainer.get("workspaceFolder")
    assert isinstance(folder, str) and folder.startswith("/work"), folder
    assert "talos" in folder.lower()


def test_run_args_pin_container_name(devcontainer: dict) -> None:
    run_args = devcontainer.get("runArgs") or []
    assert "--name=talos-devcontainer" in run_args


def test_vscode_extension_bundle_for_cluster_lab(devcontainer: dict) -> None:
    extensions = (
        (devcontainer.get("customizations") or {})
        .get("vscode", {})
        .get("extensions")
        or []
    )
    assert extensions == list(EXPECTED_EXTENSIONS)


def test_kubectl_feature_disables_minikube(devcontainer: dict) -> None:
    k8s_feature = (devcontainer.get("features") or {}).get(
        "ghcr.io/devcontainers/features/kubectl-helm-minikube:1"
    )
    assert isinstance(k8s_feature, dict)
    assert k8s_feature.get("minikube") == "none"


def test_devcontainer_uses_published_ubuntu_base_image(devcontainer: dict) -> None:
    image = devcontainer.get("image") or ""
    assert image == "mcr.microsoft.com/devcontainers/base:ubuntu"


def test_dockerfile_pins_talosctl_release(repo_root: Path) -> None:
    dockerfile = repo_root / ".devcontainer" / "Dockerfile"
    assert dockerfile.is_file(), "optional Dockerfile should remain version-pinned when present"
    text = dockerfile.read_text(encoding="utf-8")
    assert text.strip().startswith("FROM "), "Dockerfile should declare a base image"
    assert re.search(
        rf"ghcr\.io/siderolabs/talosctl:{TALOS_VERSION}",
        text,
    ), "Dockerfile must COPY talosctl matching the lab Talos release"


def test_setup_script_rejects_unsupported_architecture(repo_root: Path) -> None:
    setup = (repo_root / ".devcontainer" / "setup.sh").read_text(encoding="utf-8")
    assert "Unsupported architecture" in setup
    assert re.search(r"\*\)\s*\n\s*echo.*Unsupported architecture", setup)
