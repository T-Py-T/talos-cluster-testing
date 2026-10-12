"""Regression checks for concrete devcontainer and setup.sh wiring bugs."""

import json
import re
from pathlib import Path


def test_devcontainer_workspace_folder_matches_default_bind_mount(repo_root: Path) -> None:
    """workspaceFolder must align with the default workspaceMount target (/workspaces/...)."""
    devcontainer_path = repo_root / ".devcontainer" / "devcontainer.json"
    with devcontainer_path.open(encoding="utf-8") as handle:
        devcontainer = json.load(handle)

    folder = devcontainer.get("workspaceFolder")
    assert folder == "/workspaces/${localWorkspaceFolderBasename}", (
        "workspaceFolder must use the devcontainers default bind-mount target; "
        "a custom /work/... path leaves the editor opened away from the mounted repo"
    )
    assert "workspaceMount" not in devcontainer, (
        "custom workspaceMount requires an explicit target matching workspaceFolder"
    )


def test_setup_script_curl_fails_on_http_errors(repo_root: Path) -> None:
    setup = (repo_root / ".devcontainer" / "setup.sh").read_text(encoding="utf-8")
    assert "set -euo pipefail" in setup
    assert re.search(
        r'curl\s+-fsSL\s+"https://github\.com/siderolabs/talos/releases/download/\$\{TALOS_VERSION\}/talosctl-linux-\$\{ARCH\}"',
        setup,
    ), "talosctl download must use curl -f so failed releases abort setup instead of installing HTML"
