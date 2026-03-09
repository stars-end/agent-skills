#!/usr/bin/env python3
"""
Tests for dx-loop v1.1 fixes:
- P0: No duplicate dispatch
- P1: Notification logic
- P1: State persistence
"""

import sys
from pathlib import Path

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts" / "lib"))

from dx_loop.scheduler import DxLoopScheduler, SchedulerState
from dx_loop.state_machine import LoopState, BlockerCode, LoopStateTracker
from dx_loop.beads_integration import BeadsWaveManager
from dx_loop.blocker import BlockerClassifier
from dx_loop.notifications import NotificationManager


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


if __name__ == "__main__":
    test_no_duplicate_dispatch()
    test_notification_first_occurrence()
    test_state_persistence_round_trip()
    test_scheduler_state_persistence()
    test_restart_suppresses_unchanged_blocker_notifications()
    print("\nAll v1.1 fix tests passed!")
