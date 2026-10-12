"""Cross-manifest Talos release pin alignment and Dockerfile contract."""

import re
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
COMPOSE_PATH = REPO_ROOT / "compose.yaml"
SETUP_PATH = REPO_ROOT / ".devcontainer" / "setup.sh"
DOCKERFILE_PATH = REPO_ROOT / ".devcontainer" / "Dockerfile"

SEMVER = re.compile(r"^v\d+\.\d+\.\d+$")
TALOS_SERVICES = ("talos-cp", "talos-worker")


def _compose_talos_tag() -> str:
    with COMPOSE_PATH.open(encoding="utf-8") as handle:
        compose = yaml.safe_load(handle)
    tags = []
    for name in TALOS_SERVICES:
        image = (compose.get("services") or {})[name]["image"]
        tag = image.rsplit(":", 1)[-1]
        tags.append(tag)
    if tags[0] != tags[1]:
        raise AssertionError("control plane and worker Talos tags diverged")
    return tags[0]


def _setup_talos_version() -> str:
    text = SETUP_PATH.read_text(encoding="utf-8")
    match = re.search(r'TALOS_VERSION="(v\d+\.\d+\.\d+)"', text)
    if not match:
        raise AssertionError("setup.sh must declare TALOS_VERSION")
    return match.group(1)


def _dockerfile_talosctl_tag() -> str:
    text = DOCKERFILE_PATH.read_text(encoding="utf-8")
    match = re.search(r"ghcr\.io/siderolabs/talosctl:(v\d+\.\d+\.\d+)", text)
    if not match:
        raise AssertionError("Dockerfile must COPY talosctl from a tagged image")
    return match.group(1)


class TalosPinLockstepTests(unittest.TestCase):
    def test_compose_services_share_semver_tag(self) -> None:
        tag = _compose_talos_tag()
        self.assertRegex(tag, SEMVER)

    def test_setup_sh_talos_version_matches_compose(self) -> None:
        self.assertEqual(_setup_talos_version(), _compose_talos_tag())

    def test_dockerfile_talosctl_tag_matches_compose(self) -> None:
        self.assertEqual(_dockerfile_talosctl_tag(), _compose_talos_tag())

    def test_dockerfile_is_minimal_copy_only_toolchain_layer(self) -> None:
        text = DOCKERFILE_PATH.read_text(encoding="utf-8")
        lines = [line for line in text.splitlines() if line.strip() and not line.strip().startswith("#")]
        self.assertGreaterEqual(len(lines), 2)
        self.assertTrue(lines[0].startswith("FROM mcr.microsoft.com/devcontainers/base:"))
        self.assertRegex(
            lines[-1],
            r"^COPY --from=ghcr\.io/siderolabs/talosctl:v\d+\.\d+\.\d+ /talosctl /usr/local/bin/talosctl$",
        )
        lowered = text.lower()
        self.assertNotIn("apt-get", lowered)
        self.assertNotIn("curl ", lowered)


if __name__ == "__main__":
    unittest.main()
