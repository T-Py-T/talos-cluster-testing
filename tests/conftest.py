from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return REPO_ROOT


@pytest.fixture(scope="session")
def compose_document(repo_root: Path) -> dict:
    with (repo_root / "compose.yaml").open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)
