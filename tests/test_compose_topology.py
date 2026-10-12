"""Static policy checks for the Talos Docker Compose lab topology."""

from pathlib import Path

import pytest
import yaml

EXPECTED_TALOS_IMAGE = "ghcr.io/siderolabs/talos:v1.7.4"
REQUIRED_SERVICES = ("talos-cp", "talos-worker")
REQUIRED_VOLUMES = ("cp-state", "worker-state")


def _service(compose: dict, name: str) -> dict:
    services = compose.get("services") or {}
    assert name in services, f"missing service {name}"
    return services[name]


def test_compose_parses_as_yaml(repo_root: Path) -> None:
    path = repo_root / "compose.yaml"
    with path.open(encoding="utf-8") as handle:
        doc = yaml.safe_load(handle)
    assert isinstance(doc, dict)


def test_named_services_and_volumes(compose_document: dict) -> None:
    services = compose_document.get("services") or {}
    volumes = compose_document.get("volumes") or {}
    assert set(services) == set(REQUIRED_SERVICES)
    assert set(volumes) == set(REQUIRED_VOLUMES)


def test_talos_image_pin_matches_readme(compose_document: dict) -> None:
    for name in REQUIRED_SERVICES:
        image = _service(compose_document, name).get("image")
        assert image == EXPECTED_TALOS_IMAGE, f"{name} image pin drift"


def test_hardening_flags(compose_document: dict) -> None:
    for name in REQUIRED_SERVICES:
        svc = _service(compose_document, name)
        assert svc.get("read_only") is True, f"{name} must use read_only root"
        assert svc.get("privileged") is True, f"{name} must stay privileged for Talos-in-container"
        seccomp = svc.get("security_opt") or []
        assert "seccomp=unconfined" in seccomp, f"{name} needs seccomp=unconfined for lab"


def test_no_published_ports(compose_document: dict) -> None:
    for name in REQUIRED_SERVICES:
        ports = _service(compose_document, name).get("ports")
        assert ports in (None, []), f"{name} must not publish host ports"


def test_platform_container_env(compose_document: dict) -> None:
    for name in REQUIRED_SERVICES:
        env = _service(compose_document, name).get("environment") or []
        if isinstance(env, dict):
            assert env.get("PLATFORM") == "container"
        else:
            assert "PLATFORM=container" in env, f"{name} missing PLATFORM=container"


def test_state_volumes_mounted(compose_document: dict) -> None:
    expected = {"talos-cp": "cp-state", "talos-worker": "worker-state"}
    for svc_name, vol_name in expected.items():
        mounts = _service(compose_document, svc_name).get("volumes") or []
        joined = yaml.dump(mounts)
        assert f"{vol_name}:/system/state" in joined.replace(" ", ""), (
            f"{svc_name} must mount {vol_name} at /system/state"
        )


def test_tmpfs_runtime_paths(compose_document: dict) -> None:
    required = {"/run", "/system", "/tmp"}
    for name in REQUIRED_SERVICES:
        tmpfs = set(_service(compose_document, name).get("tmpfs") or [])
        assert required <= tmpfs, f"{name} tmpfs missing {required - tmpfs}"


def test_compose_project_name(compose_document: dict) -> None:
    assert compose_document.get("name") == "talos-workshop"


def test_hostname_matches_service_name(compose_document: dict) -> None:
    for name in REQUIRED_SERVICES:
        hostname = _service(compose_document, name).get("hostname")
        assert hostname == name, f"{name} hostname should match service name for talosctl ergonomics"
