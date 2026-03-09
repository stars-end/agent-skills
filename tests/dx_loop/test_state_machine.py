#!/usr/bin/env python3
"""
Tests for dx-loop state machine
"""

import sys
from pathlib import Path

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts" / "lib"))

from dx_loop.state_machine import LoopState, BlockerCode, LoopStateMachine, LoopStateTracker


def test_state_transitions():
    """Test basic state transitions"""
    sm = LoopStateMachine()
    
    # Initial state
    assert sm.get_state() == LoopState.PENDING
    
    # Valid transition: PENDING -> IN_PROGRESS_HEALTHY
    transition = sm.transition(LoopState.IN_PROGRESS_HEALTHY, reason="Starting")
    assert transition is not None
    assert sm.get_state() == LoopState.IN_PROGRESS_HEALTHY
    
    # Valid transition with blocker
    transition = sm.transition(LoopState.RUN_BLOCKED, blocker_code=BlockerCode.RUN_BLOCKED, reason="Provider blocked")
    assert transition is not None
    assert sm.get_state() == LoopState.RUN_BLOCKED
    assert sm.get_blocker() == BlockerCode.RUN_BLOCKED
    
    print("✓ State transitions work")


def test_unchanged_suppression():
    """Test unchanged blocker suppression"""
    tracker = LoopStateTracker()
    
    # First transition
    t1 = tracker.transition(LoopState.RUN_BLOCKED, blocker_code=BlockerCode.RUN_BLOCKED, reason="First")
    assert t1 is not None
    
    # Same state + blocker should be suppressed
    t2 = tracker.transition(LoopState.RUN_BLOCKED, blocker_code=BlockerCode.RUN_BLOCKED, reason="Second")
    assert t2 is None  # Suppressed
    
    # Different blocker should not be suppressed
    t3 = tracker.transition(LoopState.REVIEW_BLOCKED, blocker_code=BlockerCode.REVIEW_BLOCKED, reason="Third")
    assert t3 is not None
    
    print("✓ Unchanged suppression works")


def test_notification_payload():
    """Test notification payload generation"""
    tracker = LoopStateTracker()
    
    # Merge-ready should notify
    tracker.transition(LoopState.MERGE_READY, blocker_code=BlockerCode.MERGE_READY, reason="Ready")
    assert tracker.should_notify() is True
    payload = tracker.get_notification_payload()
    assert payload is not None
    assert payload["state"] == "merge_ready"
    
    print("✓ Notification payload works")


if __name__ == "__main__":
    test_state_transitions()
    test_unchanged_suppression()
    test_notification_payload()
    print("\nAll state machine tests passed!")
