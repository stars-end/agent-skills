"""Tests for deterministic artifacts + always-write outcomes."""
import json
from pathlib import Path
from unittest.mock import patch

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import ArtifactManager, Phase


class TestArtifacts:
    """Test deterministic artifact paths and outcomes."""

    def test_artifact_paths_deterministic(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            wave_id = "test-wave"
            am1 = ArtifactManager(wave_id)
            am2 = ArtifactManager(wave_id)

            assert am1.get_wave_dir() == am2.get_wave_dir()
            assert am1.get_state_file() == am2.get_state_file()
            assert am1.get_outcome_dir() == am2.get_outcome_dir()
            assert am1.get_log_dir() == am2.get_log_dir()

    def test_item_outcome_path_format(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            am = ArtifactManager("wave")
            path = am.get_item_outcome_path("bd-abc", Phase.IMPLEMENT, attempt=1)

            assert "bd-abc" in str(path)
            assert "implement" in str(path)
            assert "attempt1" in str(path)
            assert path.suffix == ".json"

    def test_outcome_written_on_timeout(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            am = ArtifactManager("timeout-wave")

            path = am.write_timeout_outcome(
                beads_id="bd-timeout",
                phase=Phase.IMPLEMENT,
                attempt=1,
                reason="Process timed out after 30 minutes"
            )

            assert path.exists()
            data = json.loads(path.read_text())
            assert data["status"] == "timeout"

    def test_outcome_written_on_cancel(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            am = ArtifactManager("cancel-wave")

            path = am.write_cancel_outcome(
                beads_id="bd-cancel",
                phase=Phase.REVIEW,
                attempt=2,
                reason="Wave cancelled by operator"
            )

            assert path.exists()
            data = json.loads(path.read_text())
            assert data["status"] == "cancelled"
