"""Tests for Beads lifecycle integration."""
import json
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import (
    WaveOrchestrator, WaveConfig, WaveState, ItemState, ItemStatus, WaveStatus,
    Verdict, Phase, ArtifactManager,
)


class TestBeadsIntegration:
    """Test Beads lifecycle integration."""

    def test_progress_updates_written(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            config = WaveConfig()
            orchestrator = WaveOrchestrator("progress-test", config)

            orchestrator.create_wave(["bd-progress-1", "bd-progress-2"])

            state = orchestrator.load_state()
            assert state.status == WaveStatus.PENDING
            assert len(state.items) == 2

            state.items[0].status = ItemStatus.IMPLEMENTING
            state.items[0].started_at = "2026-02-21T00:00:00Z"
            orchestrator.save_state()

            reloaded = orchestrator.load_state()
            assert reloaded.items[0].status == ItemStatus.IMPLEMENTING

    def test_blocked_reason_propagated(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            config = WaveConfig(max_attempts=1, retry_chain=["opencode", "blocked"])
            orchestrator = WaveOrchestrator("blocked-test", config)

            orchestrator.create_wave(["bd-blocked-1"])

            orchestrator.state.items[0].status = ItemStatus.BLOCKED
            orchestrator.state.items[0].error = "Retry chain exhausted after 1 attempt"
            orchestrator.save_state()

            reloaded = orchestrator.load_state()
            assert reloaded.items[0].status == ItemStatus.BLOCKED

    def test_no_auto_merge_policy_guard(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            config = WaveConfig()
            orchestrator = WaveOrchestrator("no-merge-test", config)

            orchestrator.create_wave(["bd-no-merge"])

            state = orchestrator.load_state()
            state.items[0].status = ItemStatus.APPROVED
            state.items[0].verdict = Verdict.APPROVED
            orchestrator.save_state()

            assert not hasattr(orchestrator, '_auto_merge')
            assert not hasattr(config, 'auto_merge')
