"""Regression: optional devcontainer Dockerfile pins talosctl via multi-stage COPY."""

import re
from pathlib import Path

import pytest

TALOS_IMAGE_PATTERN = re.compile(
    r"COPY --from=ghcr\.io/siderolabs/talosctl:(v\d+\.\d+\.\d+) /talosctl /usr/local/bin/talosctl"
)


@pytest.fixture(scope="module")
def dockerfile_text(repo_root: Path) -> str:
    path = repo_root / ".devcontainer" / "Dockerfile"
    if not path.is_file():
        pytest.skip(".devcontainer/Dockerfile not present")
    return path.read_text(encoding="utf-8")


def test_dockerfile_uses_devcontainers_base(dockerfile_text: str) -> None:
    first = dockerfile_text.strip().splitlines()[0]
    assert first.startswith("FROM mcr.microsoft.com/devcontainers/base:")


def test_dockerfile_copies_pinned_talosctl_binary(dockerfile_text: str) -> None:
    match = TALOS_IMAGE_PATTERN.search(dockerfile_text)
    assert match, "Dockerfile must COPY talosctl from a tagged ghcr.io/siderolabs/talosctl image"
    assert match.group(1).startswith("v")


def test_dockerfile_has_no_runtime_package_installs(dockerfile_text: str) -> None:
    lowered = dockerfile_text.lower()
    assert "apt-get" not in lowered
    assert "curl " not in lowered
