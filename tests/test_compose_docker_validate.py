"""Regression: compose.yaml resolves with Docker Compose (same gate as README quick start)."""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

TALOS_SERVICES = ("talos-cp", "talos-worker")
REQUIRED_VOLUMES = ("cp-state", "worker-state")


@pytest.fixture(scope="module")
def compose_config_json(repo_root: Path) -> dict:
    if shutil.which("docker") is None:
        pytest.skip("docker CLI not available in this environment")
    compose_path = repo_root / "compose.yaml"
    result = subprocess.run(
        ["docker", "compose", "-f", str(compose_path), "config", "--format", "json"],
        check=False,
        capture_output=True,
        text=True,
        cwd=repo_root,
    )
    if result.returncode != 0:
        pytest.fail(
            "docker compose config failed:\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return json.loads(result.stdout)


def test_docker_compose_resolves_project_name(compose_config_json: dict) -> None:
    assert compose_config_json.get("name") == "talos-workshop"


def test_docker_compose_resolves_both_services_without_ports(compose_config_json: dict) -> None:
    services = compose_config_json.get("services") or {}
    assert set(services) == set(TALOS_SERVICES)
    for name in TALOS_SERVICES:
        ports = services[name].get("ports")
        assert ports in (None, []), f"{name} must not publish ports after compose resolution"


def test_docker_compose_preserves_named_state_volumes(compose_config_json: dict) -> None:
    volumes = compose_config_json.get("volumes") or {}
    assert set(volumes) == set(REQUIRED_VOLUMES)


def test_compose_yaml_load_matches_docker_service_images(
    compose_document: dict, compose_config_json: dict
) -> None:
    resolved = compose_config_json.get("services") or {}
    for name in TALOS_SERVICES:
        expected = (compose_document.get("services") or {})[name]["image"]
        assert resolved[name]["image"] == expected
