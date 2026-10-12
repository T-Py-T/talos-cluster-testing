"""Regression: devcontainer.json declares the editor and feature toolchain for the lab."""

import json
from pathlib import Path

import pytest

K8S_FEATURE = "ghcr.io/devcontainers/features/kubectl-helm-minikube:1"
EXPECTED_EXTENSIONS = (
    "ms-kubernetes-tools.vscode-kubernetes-tools",
    "redhat.vscode-yaml",
    "ms-vscode.vscode-json",
    "ms-azuretools.vscode-docker",
)


@pytest.fixture(scope="session")
def devcontainer(repo_root: Path) -> dict:
    path = repo_root / ".devcontainer" / "devcontainer.json"
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def test_devcontainer_json_parses_without_trailing_commas(devcontainer: dict) -> None:
    assert devcontainer.get("name") == "Talos Cluster Testing"


def test_kubectl_feature_keeps_helm_and_disables_minikube(devcontainer: dict) -> None:
    options = (devcontainer.get("features") or {}).get(K8S_FEATURE) or {}
    assert options.get("helm") == "latest"
    assert options.get("minikube") == "none"


def test_vscode_extension_order_matches_cluster_editing_workflow(devcontainer: dict) -> None:
    extensions = (
        (devcontainer.get("customizations") or {})
        .get("vscode", {})
        .get("extensions")
        or []
    )
    assert extensions == list(EXPECTED_EXTENSIONS)


def test_devcontainer_does_not_override_docker_socket_or_mounts(devcontainer: dict) -> None:
    assert "mounts" not in devcontainer
    assert "overrideCommand" not in devcontainer
    assert "containerEnv" not in devcontainer
