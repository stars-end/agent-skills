"""Shared test fixtures for dx_batch tests."""
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))
import dx_batch  # noqa: E402


@pytest.fixture(autouse=True)
def _dx_batch_relax_cwd_and_version(monkeypatch, tmp_path):
    """Keep existing tests deterministic without host Beads dependencies."""
    monkeypatch.setattr(dx_batch, "BEADS_REPO_PATH", tmp_path)
    monkeypatch.setattr(dx_batch, "ensure_canonical_beads_cwd", lambda: (True, ""))
    monkeypatch.setattr(dx_batch, "_check_bd_version", lambda: (True, "0.56.1"))
