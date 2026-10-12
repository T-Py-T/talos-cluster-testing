"""Static policy checks for .devcontainer/devcontainer.json."""

import json
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEVCONTAINER_PATH = REPO_ROOT / ".devcontainer" / "devcontainer.json"
SETUP_PATH = REPO_ROOT / ".devcontainer" / "setup.sh"

REQUIRED_FEATURES = (
    "ghcr.io/devcontainers/features/git:1",
    "ghcr.io/devcontainers/features/github-cli:1",
    "ghcr.io/devcontainers/features/docker-in-docker:2",
    "ghcr.io/devcontainers/features/kubectl-helm-minikube:1",
)

FEATURE_VERSION_SUFFIX = re.compile(r":\d+$")


class DevcontainerManifestPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        with DEVCONTAINER_PATH.open(encoding="utf-8") as handle:
            cls.devcontainer = json.load(handle)

    def test_post_create_command_invokes_repo_relative_setup_with_bash(self) -> None:
        command = self.devcontainer.get("postCreateCommand") or ""
        self.assertEqual(command, "bash .devcontainer/setup.sh")
        self.assertTrue(SETUP_PATH.is_file(), "postCreateCommand must target an on-disk setup.sh")

    def test_feature_bundle_covers_git_github_docker_and_kubectl(self) -> None:
        features = self.devcontainer.get("features") or {}
        for feature_id in REQUIRED_FEATURES:
            self.assertIn(feature_id, features)

    def test_feature_ids_carry_explicit_version_suffixes(self) -> None:
        for feature_id in (self.devcontainer.get("features") or {}):
            self.assertRegex(
                feature_id,
                FEATURE_VERSION_SUFFIX,
                msg=f"feature {feature_id} should pin a :N devcontainer feature version",
            )

    def test_kubectl_feature_disables_minikube_but_keeps_helm(self) -> None:
        options = (self.devcontainer.get("features") or {}).get(
            "ghcr.io/devcontainers/features/kubectl-helm-minikube:1"
        )
        self.assertIsInstance(options, dict)
        self.assertEqual(options.get("minikube"), "none")
        self.assertEqual(options.get("helm"), "latest")

    def test_editor_defaults_and_cluster_extensions(self) -> None:
        vscode = (self.devcontainer.get("customizations") or {}).get("vscode") or {}
        settings = vscode.get("settings") or {}
        self.assertEqual(settings.get("terminal.integrated.defaultProfile.linux"), "bash")
        extensions = vscode.get("extensions") or []
        self.assertGreaterEqual(len(extensions), 3)
        joined = " ".join(extensions)
        self.assertIn("vscode-kubernetes-tools", joined)
        self.assertIn("vscode-docker", joined)

    def test_container_identity_and_workspace_without_socket_overrides(self) -> None:
        self.assertEqual(self.devcontainer.get("remoteUser"), "vscode")
        folder = self.devcontainer.get("workspaceFolder")
        self.assertIsInstance(folder, str)
        self.assertTrue(str(folder).startswith("/"))
        self.assertIn("talos", str(folder).lower())
        run_args = self.devcontainer.get("runArgs") or []
        self.assertIn("--name=talos-devcontainer", run_args)
        for forbidden in ("mounts", "overrideCommand", "containerEnv"):
            self.assertNotIn(forbidden, self.devcontainer)

    def test_image_uses_microsoft_devcontainers_base(self) -> None:
        image = self.devcontainer.get("image") or ""
        self.assertTrue(image.startswith("mcr.microsoft.com/devcontainers/base:"))


if __name__ == "__main__":
    unittest.main()
