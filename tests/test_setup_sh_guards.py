"""Regression: devcontainer setup.sh strict-mode and architecture guards."""

import re
from pathlib import Path

import pytest

SETUP_RELATIVE = ".devcontainer/setup.sh"


@pytest.fixture(scope="module")
def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def setup_script(repo_root: Path) -> str:
    return (repo_root / SETUP_RELATIVE).read_text(encoding="utf-8")


def test_setup_script_has_bash_shebang(setup_script: str) -> None:
    first_line = setup_script.splitlines()[0]
    assert first_line.startswith("#!/"), "setup.sh must declare an interpreter"
    assert "bash" in first_line


def test_setup_script_enables_errexit_before_work(setup_script: str) -> None:
    lines = setup_script.splitlines()
    set_e_idx = next(i for i, line in enumerate(lines) if line.strip() == "set -e")
    first_non_comment = next(
        i
        for i, line in enumerate(lines)
        if line.strip() and not line.lstrip().startswith("#")
    )
    assert set_e_idx <= first_non_comment + 2, "set -e must appear at the top of setup.sh"


def test_setup_script_maps_supported_architectures(setup_script: str) -> None:
    assert re.search(r"x86_64\)\s*\n\s*ARCH=\"amd64\"", setup_script)
    assert re.search(r"aarch64\|arm64\)\s*\n\s*ARCH=\"arm64\"", setup_script)


def test_setup_script_aborts_on_unknown_architecture(setup_script: str) -> None:
    assert "Unsupported architecture" in setup_script
    assert re.search(r"\*\)\s*\n\s*echo.*Unsupported architecture", setup_script)
    assert re.search(r"\*\)\s*\n\s*echo.*\n\s*exit 1", setup_script)


def test_setup_script_installs_talosctl_with_safe_permissions(setup_script: str) -> None:
    assert "install -m 755" in setup_script
    assert "/usr/local/bin/talosctl" in setup_script
    assert re.search(r"rm\s+/tmp/talosctl", setup_script)


def test_setup_script_download_interpolates_version_and_arch(setup_script: str) -> None:
    assert re.search(
        r"talos/releases/download/\$\{TALOS_VERSION\}/talosctl-linux-\$\{ARCH\}",
        setup_script,
    )
