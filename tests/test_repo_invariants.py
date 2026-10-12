"""Repository-level invariants referenced by README and SECURITY policy."""

from pathlib import Path


def test_license_is_mit(repo_root: Path) -> None:
    text = (repo_root / "LICENSE").read_text(encoding="utf-8")
    assert "MIT License" in text


def test_security_policy_has_reporting_section(repo_root: Path) -> None:
    text = (repo_root / "SECURITY.md").read_text(encoding="utf-8")
    assert "## Report a vulnerability" in text
    assert "Do not open a public issue" in text


def test_readme_documents_compose_validation_command(repo_root: Path) -> None:
    readme = (repo_root / "README.md").read_text(encoding="utf-8")
    assert "docker compose config" in readme
    assert EXPECTED_IMAGE_SNIPPET in readme


EXPECTED_IMAGE_SNIPPET = "ghcr.io/siderolabs/talos:v1.7.4"
