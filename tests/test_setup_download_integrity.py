"""Regression: talosctl download must not clobber /tmp or install HTML error bodies."""

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def test_setup_uses_private_tempfile_and_cleanup_trap() -> None:
    setup = (REPO_ROOT / ".devcontainer" / "setup.sh").read_text(encoding="utf-8")
    assert "mktemp" in setup, "talosctl download must use a private temp path, not a fixed /tmp/talosctl"
    assert "/tmp/talosctl" not in setup
    assert re.search(r"trap\s+'rm -f \"\$\{TALOSCTL_TMP\}\"'\s+EXIT", setup)


def test_setup_rejects_empty_or_html_download_before_install() -> None:
    setup = (REPO_ROOT / ".devcontainer" / "setup.sh").read_text(encoding="utf-8")
    assert '[[ ! -s "${TALOSCTL_TMP}" ]]' in setup
    assert "talosctl download is empty" in setup
    assert re.search(r"head -c 5.*grep -qE.*HTML", setup, re.DOTALL)
    assert "sudo install" in setup
    install_pos = setup.index("sudo install")
    empty_check_pos = setup.index("talosctl download is empty")
    assert empty_check_pos < install_pos
