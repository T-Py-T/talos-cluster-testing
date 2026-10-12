"""Compose manifest checks for Talos ephemeral volume mounts (not covered by topology-only tests)."""

from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
TALOS_SERVICES = ("talos-cp", "talos-worker")

EPHEMERAL_VOLUME_TARGETS = (
    "/var",
    "/etc/cni",
    "/etc/kubernetes",
    "/usr/libexec/kubernetes",
    "/opt",
)


@pytest.fixture(scope="module")
def repo_root() -> Path:
    return REPO_ROOT


@pytest.fixture(scope="module")
def compose_document(repo_root: Path) -> dict:
    with (repo_root / "compose.yaml").open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def _service_volumes(compose: dict, name: str) -> list:
    services = compose.get("services") or {}
    assert name in services
    return services[name].get("volumes") or []


def test_each_service_declares_ephemeral_volume_mounts(compose_document: dict) -> None:
    for service in TALOS_SERVICES:
        mounts = _service_volumes(compose_document, service)
        targets = {
            entry.get("target")
            for entry in mounts
            if isinstance(entry, dict) and entry.get("type") == "volume"
        }
        missing = set(EPHEMERAL_VOLUME_TARGETS) - targets
        assert not missing, f"{service} missing ephemeral volume targets: {sorted(missing)}"


def test_ephemeral_mounts_use_anonymous_type_volume_without_source(compose_document: dict) -> None:
    for service in TALOS_SERVICES:
        for entry in _service_volumes(compose_document, service):
            if not isinstance(entry, dict) or entry.get("type") != "volume":
                continue
            assert "source" not in entry, f"{service} ephemeral mount must omit source (Docker Compose v2)"
            assert entry.get("target") in EPHEMERAL_VOLUME_TARGETS


def test_cp_and_worker_share_identical_ephemeral_volume_block(compose_document: dict) -> None:
    def ephemeral_block(mounts: list) -> list:
        return [entry for entry in mounts if isinstance(entry, dict) and entry.get("type") == "volume"]

    cp_ephemeral = ephemeral_block(_service_volumes(compose_document, "talos-cp"))
    worker_ephemeral = ephemeral_block(_service_volumes(compose_document, "talos-worker"))
    assert cp_ephemeral == worker_ephemeral, "ephemeral volume targets should match on both nodes"


def test_state_mounts_remain_short_syntax_named_volumes(compose_document: dict) -> None:
    expected = {"talos-cp": "cp-state:/system/state", "talos-worker": "worker-state:/system/state"}
    for service, needle in expected.items():
        mounts = _service_volumes(compose_document, service)
        short = [entry for entry in mounts if isinstance(entry, str)]
        assert needle in short, f"{service} must keep named state volume short syntax"
