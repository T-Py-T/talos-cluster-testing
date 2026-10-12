"""Static contract checks for .devcontainer/setup.sh (no network execution)."""

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SETUP_PATH = REPO_ROOT / ".devcontainer" / "setup.sh"


class SetupScriptManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = SETUP_PATH.read_text(encoding="utf-8")
        cls.lines = cls.text.splitlines()

    def test_shebang_and_strict_mode_near_top(self) -> None:
        self.assertTrue(self.lines[0].startswith("#!/"))
        self.assertIn("bash", self.lines[0])
        set_e_line = next(i for i, line in enumerate(self.lines) if line.strip() == "set -e")
        first_code = next(
            i for i, line in enumerate(self.lines) if line.strip() and not line.lstrip().startswith("#")
        )
        self.assertLessEqual(set_e_line, first_code + 2)

    def test_architecture_detection_precedes_download(self) -> None:
        arch_assign = next(i for i, line in enumerate(self.lines) if line.strip().startswith("ARCH=$(uname -m)"))
        curl_line = next(i for i, line in enumerate(self.lines) if "curl " in line and "talosctl" in line)
        self.assertLess(arch_assign, curl_line)

    def test_download_uses_curl_with_follow_redirects_and_versioned_github_url(self) -> None:
        self.assertIn("curl -sL", self.text)
        self.assertNotIn("wget ", self.text)
        self.assertRegex(
            self.text,
            r"https://github\.com/siderolabs/talos/releases/download/\$\{TALOS_VERSION\}/talosctl-linux-\$\{ARCH\}",
        )

    def test_talos_version_declared_before_install(self) -> None:
        version_line = next(
            i for i, line in enumerate(self.lines) if re.search(r'TALOS_VERSION="v\d+\.\d+\.\d+"', line)
        )
        install_line = next(i for i, line in enumerate(self.lines) if "install -m 755" in line)
        self.assertLess(version_line, install_line)

    def test_install_permissions_and_temp_cleanup(self) -> None:
        self.assertIn("install -m 755", self.text)
        self.assertIn("/usr/local/bin/talosctl", self.text)
        self.assertRegex(self.text, r"rm\s+/tmp/talosctl")

    def test_verification_commands_warn_instead_of_aborting(self) -> None:
        for tool in ("talosctl version --client", "kubectl version --client", "docker --version"):
            self.assertIn(tool, self.text)
        self.assertIn("[WARN]", self.text)
        self.assertRegex(self.text, r"talosctl version --client \|\| echo \"\[WARN\]")

    def test_user_guidance_mentions_compose_and_talosctl(self) -> None:
        self.assertIn("docker compose up", self.text)
        self.assertIn("Talos cluster testing environment is ready", self.text)


if __name__ == "__main__":
    unittest.main()
