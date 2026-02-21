"""End-to-end tests for wave execution."""
import json
import os
import subprocess
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import (
    WaveOrchestrator, WaveConfig, WaveState, ItemState, ItemStatus, WaveStatus,
    Verdict, Phase, ArtifactManager, LeaseLock,
)


class TestWaveE2E:
    """End-to-end wave tests."""

    def test_wave_state_persists_across_reload(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            config = WaveConfig()
            orchestrator1 = WaveOrchestrator("persist-test", config)

            orchestrator1.create_wave(["bd-a", "bd-b"])

            orchestrator1.state.items[0].status = ItemStatus.IMPLEMENTING
            orchestrator1.state.items[0].provider = "opencode"
            orchestrator1.save_state()

            orchestrator2 = WaveOrchestrator("persist-test", config)
            state = orchestrator2.load_state()

            assert state.items[0].status == ItemStatus.IMPLEMENTING
            assert state.items[0].provider == "opencode"
            assert state.items[1].status == ItemStatus.PENDING

    def test_wave_completion_detection(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            config = WaveConfig()
            orchestrator = WaveOrchestrator("complete-test", config)

            orchestrator.create_wave(["bd-1", "bd-2"])

            for item in orchestrator.state.items:
                item.status = ItemStatus.APPROVED
                item.verdict = Verdict.APPROVED
            orchestrator.save_state()

            assert orchestrator._is_wave_complete()

    def test_partial_completion_not_done(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            config = WaveConfig()
            orchestrator = WaveOrchestrator("partial-test", config)

            orchestrator.create_wave(["bd-1", "bd-2", "bd-3"])

            orchestrator.state.items[0].status = ItemStatus.APPROVED
            orchestrator.state.items[1].status = ItemStatus.IMPLEMENTING
            orchestrator.save_state()

            assert not orchestrator._is_wave_complete()

    def test_start_fails_when_exec_cap_exceeded(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            config = WaveConfig(exec_process_cap=1)
            orchestrator = WaveOrchestrator("cap-test", config)
            orchestrator.create_wave(["bd-cap"])

            with patch("dx_batch.PreflightChecker.run", return_value=(True, {})), patch(
                "dx_batch.PreflightChecker.get_first_available_provider",
                return_value="opencode",
            ), patch.object(orchestrator, "_run_runner_prune"), patch.object(
                orchestrator.hygiene, "count_live_external_processes", return_value=(3, [1, 2, 3])
            ):
                started = orchestrator.start()

            assert not started
            assert orchestrator.state.status == WaveStatus.FAILED
            assert "exec_saturation" in (orchestrator.state.error or "")

    def test_start_runs_prune_before_loop(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            config = WaveConfig()
            orchestrator = WaveOrchestrator("prune-test", config)
            orchestrator.create_wave(["bd-prune"])

            with patch("dx_batch.PreflightChecker.run", return_value=(True, {})), patch(
                "dx_batch.PreflightChecker.get_first_available_provider",
                return_value="opencode",
            ), patch.object(
                orchestrator, "_run_runner_prune"
            ) as mock_prune, patch.object(
                orchestrator.hygiene, "count_live_external_processes", return_value=(0, [])
            ), patch.object(orchestrator, "_run_loop", return_value=True):
                started = orchestrator.start()

            assert started
            assert mock_prune.call_count == 1

    def test_run_loop_checks_doctor_before_dispatch(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            config = WaveConfig()
            orchestrator = WaveOrchestrator("doctor-cycle-test", config)
            orchestrator.create_wave(["bd-doctor-cycle"])
            orchestrator.state.status = WaveStatus.RUNNING
            orchestrator.save_state()

            with patch.object(orchestrator, "_run_dispatch_cycle_checks", return_value=True) as mock_checks, patch.object(
                orchestrator, "_is_wave_complete", return_value=True
            ):
                completed = orchestrator._run_loop()

            assert completed
            assert mock_checks.call_count == 1
