"""Regression tests for devcontainer workspace wiring and Dockerfile base alignment."""

import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEVCONTAINER_PATH = REPO_ROOT / ".devcontainer" / "devcontainer.json"
DOCKERFILE_PATH = REPO_ROOT / ".devcontainer" / "Dockerfile"
DEVCONTAINER_README = REPO_ROOT / ".devcontainer" / "README.md"


def test_devcontainer_workspace_folder_matches_default_bind_mount() -> None:
    """Opening a custom /work/... folder leaves VS Code outside the mounted repo."""
    with DEVCONTAINER_PATH.open(encoding="utf-8") as handle:
        devcontainer = json.load(handle)

    folder = devcontainer.get("workspaceFolder")
    assert folder == "/workspaces/${localWorkspaceFolderBasename}", (
        "workspaceFolder must match Dev Containers' default workspaceMount target"
    )
    assert "workspaceMount" not in devcontainer, (
        "add an explicit workspaceMount when using a non-default workspaceFolder"
    )


def test_dockerfile_base_image_matches_devcontainer_ubuntu_image() -> None:
    """Optional Dockerfile builds should use the same OS family as devcontainer.json image."""
    with DEVCONTAINER_PATH.open(encoding="utf-8") as handle:
        devcontainer = json.load(handle)

    image = devcontainer.get("image") or ""
    assert image == "mcr.microsoft.com/devcontainers/base:ubuntu"

    dockerfile = DOCKERFILE_PATH.read_text(encoding="utf-8")
    first_line = dockerfile.strip().splitlines()[0]
    assert first_line == "FROM mcr.microsoft.com/devcontainers/base:ubuntu", (
        "Dockerfile base must match devcontainer.json image so talosctl layers are consistent"
    )
    assert re.search(
        r"ghcr\.io/siderolabs/talosctl:v\d+\.\d+\.\d+",
        dockerfile,
    ), "Dockerfile must keep a pinned talosctl COPY"


def test_devcontainer_readme_documents_default_workspace_path() -> None:
    readme = DEVCONTAINER_README.read_text(encoding="utf-8")
    assert "/work/talos-cluster" not in readme, (
        "README must not document the stale /work/talos-cluster path"
    )
    assert "/workspaces/${localWorkspaceFolderBasename}" in readme
