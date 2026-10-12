"""Regression: Talos release pins stay aligned across lab manifests on main."""

import re
from pathlib import Path

import pytest
import yaml

TALOS_SERVICES = ("talos-cp", "talos-worker")
SEMVER_TAG = re.compile(r"^v\d+\.\d+\.\d+$")


@pytest.fixture(scope="module")
def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def compose_document(repo_root: Path) -> dict:
    with (repo_root / "compose.yaml").open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def _talos_version_from_compose(compose: dict) -> str:
    services = compose.get("services") or {}
    tags = []
    for name in TALOS_SERVICES:
        image = services[name].get("image", "")
        match = re.search(r":(v\d+\.\d+\.\d+)$", image)
        assert match, f"{name} image must end with :vMAJOR.MINOR.PATCH"
        tags.append(match.group(1))
    assert tags[0] == tags[1], "control plane and worker must share the same Talos tag"
    return tags[0]


def _talos_version_from_setup(repo_root: Path) -> str:
    setup = (repo_root / ".devcontainer" / "setup.sh").read_text(encoding="utf-8")
    match = re.search(r'TALOS_VERSION="(v\d+\.\d+\.\d+)"', setup)
    assert match, "setup.sh must declare TALOS_VERSION=\"vX.Y.Z\""
    return match.group(1)


def _talos_version_from_dockerfile(repo_root: Path) -> str:
    dockerfile = repo_root / ".devcontainer" / "Dockerfile"
    if not dockerfile.is_file():
        pytest.skip("Dockerfile not present")
    text = dockerfile.read_text(encoding="utf-8")
    match = re.search(r"ghcr\.io/siderolabs/talosctl:(v\d+\.\d+\.\d+)", text)
    assert match, "Dockerfile must COPY talosctl with an explicit release tag"
    return match.group(1)


def test_compose_services_use_matching_semver_tags(compose_document: dict) -> None:
    tag = _talos_version_from_compose(compose_document)
    assert SEMVER_TAG.match(tag)


def test_setup_sh_talos_version_matches_compose(repo_root: Path, compose_document: dict) -> None:
    assert _talos_version_from_setup(repo_root) == _talos_version_from_compose(compose_document)


def test_dockerfile_talosctl_tag_matches_compose(repo_root: Path, compose_document: dict) -> None:
    assert _talos_version_from_dockerfile(repo_root) == _talos_version_from_compose(compose_document)
