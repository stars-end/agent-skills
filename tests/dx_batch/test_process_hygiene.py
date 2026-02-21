"""Tests for process hygiene controls."""

import os
import time
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

import sys

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import ProcessHygiene


class TestProcessHygiene:
    """Test process hygiene controls."""

    def test_max_parallel_enforced(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            hygiene = ProcessHygiene(max_parallel=2, wave_id="test-wave")

            # Use mock to prevent _prune_dead_pids from removing our fake PIDs
            with patch.object(hygiene, "_is_pid_alive", return_value=True):
                assert hygiene.can_start_new()
                hygiene.register_pid(1001)
                assert hygiene.can_start_new()
                hygiene.register_pid(1002)
                assert not hygiene.can_start_new()

    def test_stale_pid_pruned(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            hygiene = ProcessHygiene(max_parallel=2, wave_id="test-wave")

            hygiene.register_pid(99999999)
            assert 99999999 in hygiene.child_pids

            # Real prune will remove non-existent PIDs
            hygiene._prune_dead_pids()
            assert 99999999 not in hygiene.child_pids

    def test_cleanup_runs_on_cancel(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            hygiene = ProcessHygiene(max_parallel=2, wave_id="test-wave")

            current_pid = os.getpid()
            hygiene.register_pid(current_pid)
            assert current_pid in hygiene.child_pids

            killed = hygiene.kill_all_children(exclude_pids={current_pid})
            assert killed == 0
            assert current_pid in hygiene.child_pids

    def test_count_live_external_processes_dedupes_pid_sources(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path), patch(
            "dx_batch.DX_RUNNER_LOG_BASE", tmp_path / "dx-runner"
        ):
            hygiene = ProcessHygiene(max_parallel=2, wave_id="test-wave")
            current_pid = os.getpid()

            # child pid source
            hygiene.register_pid(current_pid)

            # dx-runner plain pid source
            runner_dir = tmp_path / "dx-runner" / "opencode"
            runner_dir.mkdir(parents=True, exist_ok=True)
            (runner_dir / "a.pid").write_text(str(current_pid))

            # jobs json pid source
            jobs_dir = tmp_path / "jobs" / "other-wave"
            jobs_dir.mkdir(parents=True, exist_ok=True)
            (jobs_dir / "b.pid").write_text(f'{{"pid": {current_pid}}}')

            count, pids = hygiene.count_live_external_processes()
            assert count == 1
            assert pids == [current_pid]

    def test_count_live_external_processes_ignores_invalid_files(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path), patch(
            "dx_batch.DX_RUNNER_LOG_BASE", tmp_path / "dx-runner"
        ):
            hygiene = ProcessHygiene(max_parallel=2, wave_id="test-wave")
            runner_dir = tmp_path / "dx-runner" / "opencode"
            runner_dir.mkdir(parents=True, exist_ok=True)
            (runner_dir / "bad.pid").write_text("not-a-pid")
            (runner_dir / "empty.pid").write_text("")

            count, pids = hygiene.count_live_external_processes()
            assert count == 0
            assert pids == []
