"""Recovery and chaos tests."""
import json
import os
import time
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import (
    WaveOrchestrator, WaveConfig, WaveState, ItemState, ItemStatus, WaveStatus,
    Verdict, Phase, ArtifactManager, LeaseLock, Ledger, Doctor,
)


class TestRecoveryE2E:
    """End-to-end recovery tests."""

    def test_resume_after_controller_crash(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            config = WaveConfig(max_attempts=2)
            orchestrator1 = WaveOrchestrator("crash-test", config)

            orchestrator1.create_wave(["bd-crash-1", "bd-crash-2", "bd-crash-3"])

            orchestrator1.state.items[0].status = ItemStatus.APPROVED
            orchestrator1.state.items[0].verdict = Verdict.APPROVED
            orchestrator1.state.items[1].status = ItemStatus.IMPLEMENTING
            orchestrator1.state.items[1].provider = "opencode"
            orchestrator1.state.items[1].attempt = 1
            orchestrator1.state.items[2].status = ItemStatus.PENDING
            orchestrator1.save_state()

            del orchestrator1

            orchestrator2 = WaveOrchestrator("crash-test", config)
            state = orchestrator2.load_state()

            assert len(state.items) == 3
            assert state.items[0].status == ItemStatus.APPROVED
            assert state.items[1].status == ItemStatus.IMPLEMENTING
            assert state.items[2].status == ItemStatus.PENDING

    def test_stale_lease_recovery(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            wave_id = "stale-recovery-test"
            beads_id = "bd-stale-recovery"

            lease = LeaseLock(wave_id, beads_id, attempt=1, ttl_minutes=0)
            lease.lease_dir.mkdir(parents=True, exist_ok=True)
            lease.lease_file.write_text(json.dumps({
                "wave_id": wave_id,
                "beads_id": beads_id,
                "attempt": 1,
                "acquired_at": "2020-01-01T00:00:00Z",
                "pid": 99999,
                "ttl_minutes": 0,
            }))

            assert lease.is_stale()
            assert lease.force_release_if_stale()

    def test_outcome_written_on_timeout(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            am = ArtifactManager("timeout-outcome-test")

            path = am.write_timeout_outcome(
                beads_id="bd-timeout",
                phase=Phase.IMPLEMENT,
                attempt=1,
                reason="Process timed out"
            )

            assert path.exists()
            data = json.loads(path.read_text())
            assert data["status"] == "timeout"
