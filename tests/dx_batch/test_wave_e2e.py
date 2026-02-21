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
