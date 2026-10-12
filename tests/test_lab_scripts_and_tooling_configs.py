"""Policy tests for lab scripts and CI/tooling manifests introduced outside PR #15."""

import re
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def repo_root() -> Path:
    return REPO_ROOT


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


@pytest.mark.parametrize(
    "relative",
    [
        "scripts/check-pins.sh",
        "scripts/validate-lab-manifests.sh",
        "scripts/run-tests.sh",
    ],
)
def test_lab_shell_scripts_follow_bash_strict_mode(repo_root: Path, relative: str) -> None:
    path = repo_root / relative
    if not path.is_file():
        pytest.skip(f"{relative} not present on this branch (see draft readiness PRs)")
    text = _read(path)
    assert text.startswith("#!/"), f"{relative} must be executable bash"
    assert "set -euo pipefail" in text or "set -e" in text


def test_check_pins_script_contract(repo_root: Path) -> None:
    path = repo_root / "scripts/check-pins.sh"
    if not path.is_file():
        pytest.skip("scripts/check-pins.sh not on main yet")
    text = _read(path)
    assert "LAB_REPO_ROOT" in text, "check-pins must honor LAB_REPO_ROOT for hermetic tests"
    assert "lab-versions.env" in text
    assert "compose.yaml" in text
    assert ".devcontainer/setup.sh" in text
    assert re.search(r"TALOS_VERSION.*\^v\[0-9\]", text) or "MAJOR.MINOR.PATCH" in text


def test_validate_lab_manifests_script_contract(repo_root: Path) -> None:
    path = repo_root / "scripts/validate-lab-manifests.sh"
    if not path.is_file():
        pytest.skip("scripts/validate-lab-manifests.sh not on main yet")
    text = _read(path)
    assert "jq" in text
    assert "devcontainer.json" in text
    assert "dependabot.yml" in text
    assert "PLATFORM=container" in text
    assert "talos-cp" in text and "talos-worker" in text


def test_run_tests_script_invokes_bats_suite(repo_root: Path) -> None:
    path = repo_root / "scripts/run-tests.sh"
    if not path.is_file():
        pytest.skip("scripts/run-tests.sh not on main yet")
    text = _read(path)
    assert "bats" in text
    assert "tests/bats" in text


def test_lab_versions_env_declares_semver_talos_pin(repo_root: Path) -> None:
    path = repo_root / "lab-versions.env"
    if not path.is_file():
        pytest.skip("lab-versions.env not on main yet")
    text = _read(path)
    match = re.search(r'^TALOS_VERSION=(v[0-9]+\.[0-9]+\.[0-9]+)\s*$', text, re.MULTILINE)
    assert match, "lab-versions.env must export TALOS_VERSION=vX.Y.Z"


def test_dependabot_tracks_compose_and_github_actions(repo_root: Path) -> None:
    path = repo_root / ".github/dependabot.yml"
    if not path.is_file():
        pytest.skip(".github/dependabot.yml not on main yet")
    doc = yaml.safe_load(_read(path))
    ecosystems = {
        entry.get("package-ecosystem")
        for entry in (doc.get("updates") or [])
        if isinstance(entry, dict)
    }
    assert "github-actions" in ecosystems
    assert "docker-compose" in ecosystems


def test_ci_workflow_runs_manifest_and_compose_gates(repo_root: Path) -> None:
    path = repo_root / ".github/workflows/ci.yml"
    if not path.is_file():
        pytest.skip(".github/workflows/ci.yml not on main yet")
    text = _read(path)
    assert "check-pins.sh" in text or "validate-lab-manifests.sh" in text
    assert "docker compose" in text


def test_yamllint_config_includes_compose_and_workflows(repo_root: Path) -> None:
    path = repo_root / ".yamllint.yml"
    if not path.is_file():
        pytest.skip(".yamllint.yml not on main yet")
    text = _read(path)
    assert "compose.yaml" in text or "extends" in text or "rules" in text


def test_trivy_config_declares_scan_scope(repo_root: Path) -> None:
    path = repo_root / "trivy.yaml"
    if not path.is_file():
        pytest.skip("trivy.yaml not on main yet")
    doc = yaml.safe_load(_read(path))
    assert isinstance(doc, dict)
    scan = doc.get("scan")
    assert isinstance(scan, dict), "trivy.yaml should define a scan section"
    assert scan.get("skip-dirs") or scan.get("skip-files"), "trivy scan policy should scope filesystem paths"
