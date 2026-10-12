"""Static policy checks for compose.yaml (Talos in-container lab)."""

import re
import shutil
import subprocess
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
COMPOSE_PATH = REPO_ROOT / "compose.yaml"
TALOS_SERVICES = ("talos-cp", "talos-worker")
TALOS_IMAGE_RE = re.compile(r"^ghcr\.io/siderolabs/talos:v\d+\.\d+\.\d+$")


def _load_compose() -> dict:
    with COMPOSE_PATH.open(encoding="utf-8") as handle:
        doc = yaml.safe_load(handle)
    assert isinstance(doc, dict)
    return doc


def _service(compose: dict, name: str) -> dict:
    services = compose.get("services") or {}
    if name not in services:
        raise AssertionError(f"missing service {name}")
    return services[name]


class ComposeManifestPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.compose = _load_compose()

    def test_compose_parses_and_names_project(self) -> None:
        self.assertEqual(self.compose.get("name"), "talos-workshop")

    def test_compose_omits_legacy_top_level_version_key(self) -> None:
        self.assertNotIn("version", self.compose)

    def test_only_expected_services_and_volumes(self) -> None:
        self.assertEqual(set((self.compose.get("services") or {}).keys()), set(TALOS_SERVICES))
        volumes = self.compose.get("volumes") or {}
        self.assertEqual(set(volumes.keys()), {"cp-state", "worker-state"})
        for name, spec in volumes.items():
            self.assertIn(spec, (None, {}), msg=f"volume {name} should stay a simple named volume")

    def test_images_use_official_ghcr_talos_semver_tags(self) -> None:
        tags = []
        for name in TALOS_SERVICES:
            image = _service(self.compose, name).get("image", "")
            self.assertRegex(image, TALOS_IMAGE_RE, msg=f"{name} image must pin ghcr.io/siderolabs/talos")
            tags.append(image.split(":")[-1])
        self.assertEqual(tags[0], tags[1])

    def test_services_avoid_restart_deploy_and_healthcheck_noise(self) -> None:
        for name in TALOS_SERVICES:
            svc = _service(self.compose, name)
            for key in ("restart", "deploy", "healthcheck", "profiles"):
                self.assertNotIn(key, svc, msg=f"{name} should not set {key} in the minimal lab")

    def test_services_do_not_publish_ports_or_bind_host_paths(self) -> None:
        for name in TALOS_SERVICES:
            svc = _service(self.compose, name)
            self.assertIn(svc.get("ports"), (None, []))
            for entry in svc.get("volumes") or []:
                if isinstance(entry, str):
                    self.assertNotRegex(entry, r"^/", msg="host bind mounts are forbidden")
                elif isinstance(entry, dict):
                    self.assertEqual(entry.get("type"), "volume")
                    self.assertNotIn("source", entry)

    def test_control_plane_and_worker_blocks_match_except_identity(self) -> None:
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

        cp = normalized(_service(self.compose, "talos-cp"))
        worker = normalized(_service(self.compose, "talos-worker"))
        self.assertEqual(cp, worker)


@unittest.skipUnless(shutil.which("docker"), "docker CLI not available")
class ComposeDockerComposeConfigTests(unittest.TestCase):
    def test_docker_compose_config_resolves_manifest(self) -> None:
        result = subprocess.run(
            ["docker", "compose", "-f", str(COMPOSE_PATH), "config", "--format", "json"],
            check=False,
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
        )
        self.assertEqual(
            result.returncode,
            0,
            msg=f"docker compose config failed:\n{result.stdout}\n{result.stderr}",
        )
        import json

        resolved = json.loads(result.stdout)
        self.assertEqual(resolved.get("name"), "talos-workshop")
        self.assertEqual(set((resolved.get("services") or {}).keys()), set(TALOS_SERVICES))


if __name__ == "__main__":
    unittest.main()
