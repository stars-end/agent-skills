"""Tests for dx-batch doctor diagnostics."""
import json
import os
from pathlib import Path
from unittest.mock import patch

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import Doctor, WaveState, WaveStatus, ItemState, ItemStatus, Phase, ArtifactManager, LeaseLock


class TestDoctor:
    """Test doctor diagnostics."""

    def test_detects_stale_lease(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            wave_id = "stale-lease-test"

            state = WaveState(
                wave_id=wave_id,
                status=WaveStatus.RUNNING,
                items=[ItemState(beads_id="bd-stale", status=ItemStatus.IMPLEMENTING)],
            )
            am = ArtifactManager(wave_id)
            am.ensure_dirs()
            am.get_state_file().write_text(json.dumps(state.to_dict()))

            lease_dir = tmp_path / "leases" / wave_id
            lease_dir.mkdir(parents=True, exist_ok=True)

            stale_lease = lease_dir / "bd-stale+attempt1.lock"
            stale_lease.write_text(json.dumps({
                "beads_id": "bd-stale",
                "attempt": 1,
                "acquired_at": "2020-01-01T00:00:00Z",
                "ttl_minutes": 0,
            }))

            doctor = Doctor(wave_id)
            result = doctor.diagnose()

            assert "issues" in result
            stale_issues = [i for i in result["issues"] if i.get("type") == "stale_lease"]
            assert len(stale_issues) >= 1

    def test_detects_missing_outcome(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            wave_id = "missing-outcome-test"

            item = ItemState(
                beads_id="bd-missing",
                status=ItemStatus.IMPLEMENTING,
                phase=Phase.IMPLEMENT,
                outcome_path="/nonexistent/outcome.json",
            )
            state = WaveState(
                wave_id=wave_id,
                status=WaveStatus.RUNNING,
                items=[item],
            )

            am = ArtifactManager(wave_id)
            am.ensure_dirs()
            am.get_state_file().write_text(json.dumps(state.to_dict()))

            doctor = Doctor(wave_id)
            result = doctor.diagnose()

            missing_issues = [i for i in result["issues"] if i.get("type") == "missing_outcome"]
            assert len(missing_issues) >= 1
