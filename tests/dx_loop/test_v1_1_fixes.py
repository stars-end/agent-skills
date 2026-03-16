#!/usr/bin/env python3
"""
Tests for dx-loop v1.1 fixes:
- P0: No duplicate dispatch
- P1: Notification logic
- P1: State persistence
- Operator surface fixes
"""

import json
import sys
import subprocess
from pathlib import Path
from types import SimpleNamespace
import importlib.util

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts" / "lib"))

from dx_loop.scheduler import DxLoopScheduler, SchedulerState
from dx_loop.state_machine import LoopState, BlockerCode, LoopStateTracker
from dx_loop.beads_integration import BeadsTask, BeadsWaveManager
from dx_loop.blocker import BlockerClassifier
from dx_loop.notifications import NotificationManager

REPO_ROOT = Path(__file__).parent.parent.parent
DX_LOOP_SPEC = importlib.util.spec_from_file_location(
    "dx_loop_script", REPO_ROOT / "scripts" / "dx_loop.py"
)
dx_loop_script = importlib.util.module_from_spec(DX_LOOP_SPEC)
assert DX_LOOP_SPEC.loader is not None
DX_LOOP_SPEC.loader.exec_module(dx_loop_script)
DxLoop = dx_loop_script.DxLoop
cmd_status = dx_loop_script.cmd_status


def test_no_duplicate_dispatch():
    """P0 fix: Active work not redispatched"""
    scheduler = DxLoopScheduler(cadence_seconds=1)
    
    # Mark as active
    scheduler.state.mark_dispatched("bd-test-1")
    
    # Should be active
    assert scheduler.state.is_active("bd-test-1")
    
    # Mark as completed
    scheduler.state.mark_completed("bd-test-1")
    
    # Should not be active, should be completed
    assert not scheduler.state.is_active("bd-test-1")
    assert scheduler.state.is_completed("bd-test-1")
    
    print("✓ No duplicate dispatch works")


def test_notification_first_occurrence():
    """P1 fix: Blocked notifications emit on FIRST occurrence"""
    tracker = LoopStateTracker()
    
    # First occurrence - should emit
    t1 = tracker.transition(
        LoopState.RUN_BLOCKED,
        blocker_code=BlockerCode.RUN_BLOCKED,
        reason="First"
    )
    assert t1 is not None, "First occurrence should emit"
    
    # Second occurrence (unchanged) - should be suppressed
    t2 = tracker.transition(
        LoopState.RUN_BLOCKED,
        blocker_code=BlockerCode.RUN_BLOCKED,
        reason="Second"
    )
    assert t2 is None, "Unchanged second occurrence should be suppressed"
    
    # Different blocker - should emit
    t3 = tracker.transition(
        LoopState.REVIEW_BLOCKED,
        blocker_code=BlockerCode.REVIEW_BLOCKED,
        reason="Third"
    )
    assert t3 is not None, "Different blocker should emit"
    
    print("✓ Notification first occurrence works")


def test_state_persistence_round_trip():
    """P1 fix: Save/load is symmetric"""
    # Create manager with data
    manager1 = BeadsWaveManager()
    from dx_loop.beads_integration import BeadsTask

    manager1.tasks = {
        "bd-1": BeadsTask(
            beads_id="bd-1",
            title="Test",
            status="open",
            dependencies=[],
            dependents=[],
            priority=2,
        )
    }
    manager1.layers = [["bd-1"]]
    manager1.completed = {"bd-0"}
    
    # Save
    state_dict = manager1.to_dict()
    
    # Load
    manager2 = BeadsWaveManager.from_dict(state_dict)
    
    # Verify symmetric
    assert "bd-1" in manager2.tasks
    assert manager2.tasks["bd-1"].title == "Test"
    assert manager2.layers == [["bd-1"]]
    assert manager2.completed == {"bd-0"}
    
    print("✓ State persistence round-trip works")


def test_scheduler_state_persistence():
    """Scheduler state save/load"""
    state1 = SchedulerState()
    state1.active_beads_ids = {"bd-1", "bd-2"}
    state1.completed_beads_ids = {"bd-0"}
    state1.dispatch_count = 5
    
    # Save
    data = state1.to_dict()
    
    # Load
    state2 = SchedulerState.from_dict(data)
    
    # Verify
    assert state2.active_beads_ids == {"bd-1", "bd-2"}
    assert state2.completed_beads_ids == {"bd-0"}
    assert state2.dispatch_count == 5
    
    print("✓ Scheduler state persistence works")


def test_restart_suppresses_unchanged_blocker_notifications():
    """P1 fix: blocker suppression survives classifier/notification restore"""
    classifier1 = BlockerClassifier()
    notifications1 = NotificationManager()

    blocker1 = classifier1.classify(
        "worktree_missing",
        beads_id="bd-test-1",
        wave_id="wave-test",
    )
    note1 = notifications1.create_notification(blocker1)

    assert note1 is not None, "First blocker occurrence should notify"

    classifier2 = BlockerClassifier.from_dict(classifier1.to_dict())
    notifications2 = NotificationManager.from_dict(notifications1.to_dict())

    blocker2 = classifier2.classify(
        "worktree_missing",
        beads_id="bd-test-1",
        wave_id="wave-test",
    )
    note2 = notifications2.create_notification(blocker2)

    assert blocker2.is_unchanged, "Same blocker after restore should be unchanged"
    assert note2 is None, "Unchanged blocker after restore should be suppressed"

    print("✓ Restart preserves unchanged-blocker suppression")


def test_describe_wave_readiness_reports_dependency_blockers():
    """Dependency-blocked zero-dispatch waves should report unmet dependencies."""
    manager = BeadsWaveManager()
    manager.tasks = {
        "bd-ready": BeadsTask(
            beads_id="bd-ready",
            title="Ready task",
            dependencies=[],
        ),
        "bd-blocked": BeadsTask(
            beads_id="bd-blocked",
            title="Blocked task",
            dependencies=["bd-upstream"],
        ),
    }
    manager.completed = {"bd-ready"}

    readiness = manager.describe_wave_readiness()

    assert readiness.ready == []
    assert readiness.pending_tasks == ["bd-blocked"]
    assert readiness.waiting_on_dependencies == [
        {
            "beads_id": "bd-blocked",
            "title": "Blocked task",
            "unmet_dependencies": ["bd-upstream"],
            "dependency_statuses": {"bd-upstream": "external_or_incomplete"},
        }
    ]

    print("✓ Dependency-blocked waves are classified explicitly")


def test_status_outputs_waiting_on_dependency_details(tmp_path, capsys):
    """Human-readable status should explain dependency-blocked zero-dispatch waves."""
    wave_id = "wave-operator-status-test"
    loop = DxLoop(wave_id)
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-blocked": BeadsTask(
            beads_id="bd-blocked",
            title="Blocked task",
            dependencies=["bd-upstream"],
        )
    }
    loop.scheduler.state.blocked_beads_ids = {"bd-blocked"}
    loop._set_wave_status(
        LoopState.WAITING_ON_DEPENDENCY,
        BlockerCode.WAITING_ON_DEPENDENCY,
        "No dispatches: waiting on dependencies for 1 task(s)",
        blocked_details=[
            {
                "beads_id": "bd-blocked",
                "title": "Blocked task",
                "unmet_dependencies": ["bd-upstream"],
                "dependency_statuses": {"bd-upstream": "external_or_incomplete"},
            }
        ],
    )
    loop._save_state()

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(SimpleNamespace(wave_id=wave_id, json=False))
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    assert "State: waiting_on_dependency" in captured.out
    assert "Blocker Code: waiting_on_dependency" in captured.out
    assert "Waiting on dependencies:" in captured.out
    assert "bd-blocked: bd-upstream" in captured.out

    print("✓ Status output explains dependency blockers")


def test_run_loop_exits_when_initial_frontier_is_fully_blocked(tmp_path):
    """A zero-dispatch blocked start should persist state and exit promptly."""
    wave_id = "wave-blocked-at-start"
    loop = DxLoop(wave_id, config={"cadence_seconds": 1})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-blocked-1": BeadsTask(
            beads_id="bd-blocked-1",
            title="Blocked task 1",
            dependencies=["bd-upstream"],
        ),
        "bd-blocked-2": BeadsTask(
            beads_id="bd-blocked-2",
            title="Blocked task 2",
            dependencies=["bd-blocked-1"],
        ),
    }
    loop.beads_manager.layers = [["bd-blocked-1"], ["bd-blocked-2"]]

    assert loop.run_loop(max_iterations=2) is True

    state = json.loads(loop.state_file.read_text())
    assert state["scheduler_state"]["dispatch_count"] == 0
    assert state["wave_status"]["state"] == "waiting_on_dependency"
    assert (
        state["wave_status"]["reason"]
        == "Initial frontier blocked with 2 task(s); exiting without resident loop"
    )
    assert len(state["wave_status"]["blocked_details"]) == 2

    print("✓ Blocked-at-start waves exit promptly")


def test_dx_ensure_bins_links_dx_loop(tmp_path):
    """dx-loop should be linked into the canonical operator bin dir and execute."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()

    result = subprocess.run(
        ["bash", str(REPO_ROOT / "scripts" / "dx-ensure-bins.sh")],
        env={
            "PATH": "/usr/bin:/bin",
            "HOME": str(tmp_path),
            "AGENTS_ROOT": str(REPO_ROOT),
            "BIN_DIR": str(bin_dir),
        },
        capture_output=True,
        text=True,
        check=True,
    )

    assert "ensured ~/bin tools" in result.stdout
    linked = bin_dir / "dx-loop"
    assert linked.is_symlink()
    assert linked.resolve() == REPO_ROOT / "scripts" / "dx-loop"

    version = subprocess.run(
        [str(linked), "--version"],
        env={
            "PATH": f"{bin_dir}:/usr/bin:/bin",
            "HOME": str(tmp_path),
        },
        capture_output=True,
        text=True,
        check=True,
    )
    assert "dx-loop 1.1.0" in version.stdout

    print("✓ dx-loop canonical entrypoint is linked")


if __name__ == "__main__":
    test_no_duplicate_dispatch()
    test_notification_first_occurrence()
    test_state_persistence_round_trip()
    test_scheduler_state_persistence()
    test_restart_suppresses_unchanged_blocker_notifications()
    test_describe_wave_readiness_reports_dependency_blockers()
    print("\nAll v1.1 fix tests passed!")
