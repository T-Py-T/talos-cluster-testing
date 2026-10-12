"""Regression: setup must fail when talosctl client verification fails after install."""

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def test_setup_fails_when_talosctl_client_verification_fails() -> None:
    setup = (REPO_ROOT / ".devcontainer" / "setup.sh").read_text(encoding="utf-8")
    assert "talosctl version --client || echo" not in setup, (
        "setup must not warn-and-continue when talosctl client verification fails"
    )
    assert re.search(
        r"if ! talosctl version --client",
        setup,
    ), "setup should gate success on talosctl client verification"
    assert "talosctl client failed verification after install" in setup
