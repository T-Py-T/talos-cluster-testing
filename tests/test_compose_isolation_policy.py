"""Regression: Compose lab keeps nodes isolated (no extra exposure or coupling)."""

import pytest

TALOS_SERVICES = ("talos-cp", "talos-worker")


def _service(compose: dict, name: str) -> dict:
    services = compose.get("services") or {}
    assert name in services, f"missing service {name}"
    return services[name]


def test_compose_has_no_custom_networks_or_secrets(compose_document: dict) -> None:
    assert "networks" not in compose_document, "lab should use the default bridge only"
    assert "secrets" not in compose_document
    assert "configs" not in compose_document


def test_services_do_not_depend_on_each_other(compose_document: dict) -> None:
    for name in TALOS_SERVICES:
        svc = _service(compose_document, name)
        assert "depends_on" not in svc, f"{name} must start independently for lab exercises"
        assert "links" not in svc


def test_services_avoid_host_integration_shortcuts(compose_document: dict) -> None:
    forbidden = (
        "container_name",
        "extra_hosts",
        "devices",
        "cap_add",
        "cap_drop",
        "cgroup",
        "userns_mode",
        "env_file",
    )
    for name in TALOS_SERVICES:
        svc = _service(compose_document, name)
        for key in forbidden:
            assert key not in svc, f"{name} should not set {key} in the minimal lab manifest"


def test_services_use_image_pull_only(compose_document: dict) -> None:
    for name in TALOS_SERVICES:
        svc = _service(compose_document, name)
        assert "image" in svc and "build" not in svc, f"{name} must pull a pinned image, not build"
        assert not str(svc.get("image", "")).startswith("."), f"{name} image must be a registry reference"
