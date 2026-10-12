"""Regression: setup.sh documents post-install smoke checks for the lab toolchain."""

import re
from pathlib import Path

import pytest

SETUP = ".devcontainer/setup.sh"


@pytest.fixture(scope="module")
def setup_script(repo_root: Path) -> str:
    return (repo_root / SETUP).read_text(encoding="utf-8")


def test_setup_script_verifies_core_cli_tools(setup_script: str) -> None:
    checks = (
        r"talosctl version --client",
        r"kubectl version --client",
        r"docker --version",
        r"docker compose version",
    )
    for pattern in checks:
        assert re.search(pattern, setup_script), f"setup.sh should run `{pattern}` smoke check"


def test_setup_script_warns_instead_of_failing_optional_checks(setup_script: str) -> None:
    assert "[WARN]" in setup_script
    assert re.search(r"talosctl version --client \|\| echo \"\[WARN\]", setup_script)


def test_setup_script_prints_lab_next_steps(setup_script: str) -> None:
    assert "docker compose up" in setup_script
    assert "talosctl" in setup_script
    assert "Talos cluster testing environment is ready" in setup_script


def test_setup_script_cleans_temporary_talosctl_binary(setup_script: str) -> None:
    assert "/tmp/talosctl" in setup_script
    assert re.search(r"rm\s+/tmp/talosctl", setup_script)
