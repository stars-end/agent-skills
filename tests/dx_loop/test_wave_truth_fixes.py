#!/usr/bin/env python3
"""
Regression tests for dx-loop wave truth fixes (bd-5w5o.56):

Fix A: approved review closes task in Beads truthfully
  - close_beads_task() calls bd close and updates local status
  - both completion paths surface close failures via stderr warning

Fix B: rehydration timeout no longer traps fork/join tasks
  - describe_wave_readiness() default timeout raised from 3s to 10s
  - refresh_unhydrated_tasks() default timeout raised from 3s to 10s
"""

import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
import importlib.util

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts" / "lib"))

from dx_loop.beads_integration import BeadsTask, BeadsWaveManager
from dx_loop.baton import BatonPhase, BatonManager, ReviewVerdict
from dx_loop.state_machine import LoopState, BlockerCode

REPO_ROOT = Path(__file__).parent.parent.parent
DX_LOOP_SPEC = importlib.util.spec_from_file_location(
    "dx_loop_script", REPO_ROOT / "scripts" / "dx_loop.py"
)
dx_loop_script = importlib.util.module_from_spec(DX_LOOP_SPEC)
assert DX_LOOP_SPEC.loader is not None
DX_LOOP_SPEC.loader.exec_module(dx_loop_script)
DxLoop = dx_loop_script.DxLoop


# --- Fix A regression tests ---


def test_close_beads_task_updates_status_on_success(monkeypatch):
    """close_beads_task should update task.status and dependency cache on success."""
    manager = BeadsWaveManager()
    manager.tasks["bd-test"] = BeadsTask(
        beads_id="bd-test",
        title="Test task",
        status="open",
    )

    def fake_run(cmd, **kwargs):
        assert cmd[:3] == ["bd", "close", "bd-test"]
        return subprocess.CompletedProcess(cmd, 0, stdout="OK", stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    result = manager.close_beads_task("bd-test", reason="dx-loop: test")

    assert result is True
    assert manager.tasks["bd-test"].status == "closed"
    assert manager.dependency_status_cache["bd-test"] == "closed"


def test_close_beads_task_returns_false_on_failure(monkeypatch):
    """close_beads_task should return False without crashing when bd close fails."""
    manager = BeadsWaveManager()
    manager.tasks["bd-test"] = BeadsTask(
        beads_id="bd-test",
        title="Test task",
        status="open",
    )

    def fake_run(cmd, **kwargs):
        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="error: not found")

    monkeypatch.setattr(subprocess, "run", fake_run)

    result = manager.close_beads_task("bd-test", reason="dx-loop: test")

    assert result is False
    assert manager.tasks["bd-test"].status == "open"


def test_close_beads_task_returns_false_on_timeout(monkeypatch):
    """close_beads_task should return False on subprocess timeout."""
    manager = BeadsWaveManager()
    manager.tasks["bd-test"] = BeadsTask(
        beads_id="bd-test",
        title="Test task",
        status="open",
    )

    def fake_run(cmd, **kwargs):
        raise subprocess.TimeoutExpired(cmd=cmd, timeout=10)

    monkeypatch.setattr(subprocess, "run", fake_run)

    result = manager.close_beads_task("bd-test", reason="dx-loop: test")

    assert result is False
    assert manager.tasks["bd-test"].status == "open"


def test_approved_review_path_warns_on_close_failure(monkeypatch, capsys):
    """Review APPROVED path should log stderr warning when bd close fails."""
    loop = DxLoop("wave-test-close-warn")
    loop.beads_manager.tasks["bd-task"] = BeadsTask(
        beads_id="bd-task",
        title="Test task",
        status="open",
        dependencies=[],
    )
    loop.baton_manager.start_implement("bd-task")
    loop.baton_manager.complete_implement(
        "bd-task",
        pr_url="https://github.com/example/pull/1",
        pr_head_sha="a" * 40,
    )
    loop.baton_manager.start_review("bd-task", run_id="review-1")

    loop.review_runner = MagicMock()
    loop.review_runner.check.return_value = MagicMock(
        beads_id="bd-task-review",
        state="exited_ok",
        exit_code=0,
    )
    loop.review_runner.extract_verdict_sidecar.return_value = None
    loop.review_runner.report.return_value = {"verdict": "APPROVED", "detail": "ok"}
    loop.review_runner.extract_review_verdict.return_value = None

    close_call_count = {"n": 0}

    def fake_close(beads_id, reason=""):
        close_call_count["n"] += 1
        return False

    loop.beads_manager.close_beads_task = fake_close

    loop._check_review_progress("bd-task")

    captured = capsys.readouterr()
    assert close_call_count["n"] == 1
    assert "WARNING: bd close failed for bd-task" in captured.err
    assert "wave truth is complete but Beads may still show open" in captured.err


def test_no_review_path_warns_on_close_failure(monkeypatch, capsys):
    """No-review completion path should log stderr warning when bd close fails."""
    loop = DxLoop("wave-test-no-review-warn")
    loop.beads_manager.tasks["bd-task"] = BeadsTask(
        beads_id="bd-task",
        title="Test task",
        status="open",
        dependencies=[],
    )
    loop.baton_manager.start_implement("bd-task", run_id="run-1")
    loop.config["require_review"] = False
    loop.implement_runner = MagicMock()
    loop.implement_runner.check.return_value = MagicMock(
        beads_id="bd-task",
        state="exited_ok",
        exit_code=0,
    )
    loop.implement_runner.extract_pr_artifacts.return_value = None
    loop.implement_runner.extract_agent_output.return_value = (
        "## Tech Lead Review (Implementation Return)\n"
        "- MODE: implementation_return\n"
        "- PR_URL: https://github.com/example/pull/1\n"
        "- PR_HEAD_SHA: " + "a" * 40 + "\n"
        "- BEADS_SUBTASK: bd-task\n"
    )

    close_call_count = {"n": 0}

    def fake_close(beads_id, reason=""):
        close_call_count["n"] += 1
        return False

    loop.beads_manager.close_beads_task = fake_close

    loop._check_implement_progress("bd-task")

    captured = capsys.readouterr()
    assert close_call_count["n"] == 1
    assert "WARNING: bd close failed for bd-task" in captured.err


def test_close_beads_task_round_trip_persistence():
    """Closed task status should survive save/load round-trip."""
    manager1 = BeadsWaveManager()
    manager1.tasks["bd-task"] = BeadsTask(
        beads_id="bd-task",
        title="Test task",
        status="closed",
        details_loaded=True,
    )
    manager1.completed = {"bd-task"}
    manager1.dependency_status_cache["bd-task"] = "closed"
    manager1.layers = [["bd-task"]]

    state = manager1.to_dict()
    manager2 = BeadsWaveManager.from_dict(state)

    assert manager2.tasks["bd-task"].status == "closed"
    assert "bd-task" in manager2.completed
    assert manager2.dependency_status_cache["bd-task"] == "closed"
    assert manager2._is_dependency_satisfied("bd-task")


# --- Fix B regression tests ---


def test_describe_wave_readiness_default_timeout_is_10():
    """describe_wave_readiness default timeout should be 10s, not 3s."""
    import inspect

    sig = inspect.signature(BeadsWaveManager.describe_wave_readiness)
    timeout_param = sig.parameters["timeout_seconds"]
    assert timeout_param.default == 10


def test_refresh_unhydrated_tasks_default_timeout_is_10():
    """refresh_unhydrated_tasks default timeout should be 10s, not 3s."""
    import inspect

    sig = inspect.signature(BeadsWaveManager.refresh_unhydrated_tasks)
    timeout_param = sig.parameters["timeout_seconds"]
    assert timeout_param.default == 10


def test_rehydration_unblocks_fork_join_after_timeout_fix(monkeypatch):
    """
    Simulate the golden fixture shape: 5 tasks, fork at .3/.4, join at .5.
    After rehydration with 10s budget, all tasks should be dispatchable in
    correct topological order.
    """
    manager = BeadsWaveManager()
    manager.tasks = {
        "bd-ep.1": BeadsTask(
            beads_id="bd-ep.1",
            title="Append line 1",
            status="open",
            dependencies=[],
            details_loaded=True,
        ),
        "bd-ep.2": BeadsTask(
            beads_id="bd-ep.2",
            title="Append line 2",
            status="open",
            dependencies=["bd-ep.1"],
            details_loaded=False,
            detail_load_error="timeout",
        ),
        "bd-ep.3": BeadsTask(
            beads_id="bd-ep.3",
            title="Append line 3",
            status="open",
            dependencies=["bd-ep.2"],
            details_loaded=False,
            detail_load_error="timeout",
        ),
        "bd-ep.4": BeadsTask(
            beads_id="bd-ep.4",
            title="Append line 4",
            status="open",
            dependencies=["bd-ep.2"],
            details_loaded=False,
            detail_load_error="timeout",
        ),
        "bd-ep.5": BeadsTask(
            beads_id="bd-ep.5",
            title="Append line 5",
            status="open",
            dependencies=["bd-ep.3", "bd-ep.4"],
            details_loaded=False,
            detail_load_error="timeout",
        ),
    }

    hydration_calls = []

    def fake_load_details(task, timeout_seconds=3):
        hydration_calls.append((task.beads_id, timeout_seconds))
        task.details_loaded = True
        task.detail_load_error = None
        return task

    monkeypatch.setattr(manager, "_load_task_details", fake_load_details)

    manager.describe_wave_readiness()

    assert len(hydration_calls) == 4
    for task_id, timeout in hydration_calls:
        assert timeout == 10, (
            f"Task {task_id} hydrated with timeout={timeout}, expected 10"
        )

    assert all(t.details_loaded for t in manager.tasks.values())

    readiness = manager.describe_wave_readiness()
    assert readiness.ready == ["bd-ep.1"]


def test_pre_closed_deps_do_not_block_dispatch_without_pr_artifacts():
    """
    Bug C regression: a task whose upstream deps are pre-closed (not dispatched
    by this wave) should still be dispatchable even when PR artifacts cannot be
    recovered. Terminal status in dependency_status_cache is sufficient.
    """
    loop = DxLoop("wave-test-bug-c")
    loop.beads_manager.tasks["bd-child"] = BeadsTask(
        beads_id="bd-child",
        title="Join task",
        dependencies=["bd-parent-a", "bd-parent-b"],
    )
    loop.beads_manager.completed = {"bd-parent-a", "bd-parent-b"}
    loop.beads_manager.dependency_status_cache["bd-parent-a"] = "closed"
    loop.beads_manager.dependency_status_cache["bd-parent-b"] = "closed"
    loop.beads_manager.dependency_metadata_cache["bd-parent-a"] = {
        "title": "Parent A",
        "repo": "agent-skills",
        "status": "closed",
        "close_reason": "Manually closed",
    }
    loop.beads_manager.dependency_metadata_cache["bd-parent-b"] = {
        "title": "Parent B",
        "repo": "agent-skills",
        "status": "closed",
        "close_reason": "Manually closed",
    }

    result = loop._check_dependency_artifacts("bd-child")

    assert result is None


def test_non_terminal_completed_dep_still_blocks():
    """A completed dep with non-terminal cached status should still block."""
    loop = DxLoop("wave-test-non-terminal")
    loop.beads_manager.tasks["bd-child"] = BeadsTask(
        beads_id="bd-child",
        title="Child task",
        dependencies=["bd-parent"],
    )
    loop.beads_manager.completed = {"bd-parent"}
    loop.beads_manager.dependency_status_cache["bd-parent"] = "open"

    result = loop._check_dependency_artifacts("bd-child")

    assert result is not None
    assert "bd-parent" in result["missing_dependencies"]


if __name__ == "__main__":
    import pytest

    pytest.main([__file__, "-v"])
