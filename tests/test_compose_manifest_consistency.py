"""Regression: compose.yaml structural consistency and lab safety invariants."""

from pathlib import Path

import pytest
import yaml

TALOS_SERVICES = ("talos-cp", "talos-worker")
STATE_MOUNTS = {
    "talos-cp": "cp-state:/system/state",
    "talos-worker": "worker-state:/system/state",
}
ANONYMOUS_TARGETS = (
    "/var",
    "/etc/cni",
    "/etc/kubernetes",
    "/usr/libexec/kubernetes",
    "/opt",
)


@pytest.fixture(scope="module")
def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def compose_document(repo_root: Path) -> dict:
    with (repo_root / "compose.yaml").open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def _service(compose: dict, name: str) -> dict:
    services = compose.get("services") or {}
    assert name in services
    return services[name]


def test_compose_omits_obsolete_top_level_version_key(compose_document: dict) -> None:
    assert "version" not in compose_document, "Compose v2 projects should not pin a legacy version key"


def test_named_volumes_are_declared_without_external_drivers(compose_document: dict) -> None:
    volumes = compose_document.get("volumes") or {}
    assert set(volumes) == {"cp-state", "worker-state"}
    for name, spec in volumes.items():
        assert spec in (None, {}), f"volume {name} should be a simple named volume"


def test_services_do_not_build_images_or_escalate_host_namespaces(compose_document: dict) -> None:
    forbidden = ("build", "network_mode", "pid", "ipc")
    for name in TALOS_SERVICES:
        svc = _service(compose_document, name)
        for key in forbidden:
            assert key not in svc, f"{name} must not set {key} for the in-container lab"


def test_services_have_no_host_bind_mounts(compose_document: dict) -> None:
    for name in TALOS_SERVICES:
        mounts = _service(compose_document, name).get("volumes") or []
        for entry in mounts:
            if isinstance(entry, str):
                assert ":" in entry and not entry.startswith("/"), (
                    f"{name} must not bind-mount host paths ({entry})"
                )
            elif isinstance(entry, dict):
                assert entry.get("type") == "volume", f"{name} unexpected mount type: {entry}"
                assert "source" not in entry


def test_each_service_mount_inventory_matches_lab_template(compose_document: dict) -> None:
    for name in TALOS_SERVICES:
        mounts = _service(compose_document, name).get("volumes") or []
        short = [m for m in mounts if isinstance(m, str)]
        long_form = [m for m in mounts if isinstance(m, dict)]
        assert short == [STATE_MOUNTS[name]]
        assert {m.get("target") for m in long_form} == set(ANONYMOUS_TARGETS)


def test_control_plane_and_worker_service_blocks_match_except_identity(
    compose_document: dict,
) -> None:
    def normalized(svc: dict) -> dict:
        clone = dict(svc)
        clone.pop("hostname", None)
        volumes = []
        for entry in clone.get("volumes") or []:
            if isinstance(entry, str) and entry.endswith(":/system/state"):
                volumes.append("STATE_VOLUME")
            else:
                volumes.append(entry)
        clone["volumes"] = volumes
        return clone

    cp = normalized(_service(compose_document, "talos-cp"))
    worker = normalized(_service(compose_document, "talos-worker"))
    assert cp == worker
