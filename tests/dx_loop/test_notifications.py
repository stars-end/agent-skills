#!/usr/bin/env python3
"""
Tests for bd-5w5o.10: operator handoff and low-noise notification policy.

Covers:
- emit on first blocked occurrence
- suppress unchanged repeats
- quiet healthy/pending behavior
- merge_ready emission with PR handoff payload
- needs_decision emission with triage context
- unchanged blocked state suppression
- operator payload structure
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts" / "lib"))

from dx_loop.state_machine import (
    LoopState,
    BlockerCode,
    LoopStateTracker,
    LoopStateMachine,
)
from dx_loop.blocker import BlockerState, BlockerSeverity, BlockerClassifier
from dx_loop.notifications import Notification, NotificationManager


def test_healthy_state_does_not_notify():
    tracker = LoopStateTracker()
    tracker.transition(LoopState.IN_PROGRESS_HEALTHY, reason="Making progress")
    assert tracker.should_notify() is False
    print("[quiet-healthy] healthy state does not notify")


def test_pending_state_does_not_notify():
    tracker = LoopStateTracker()
    tracker.transition(LoopState.PENDING, reason="Waiting")
    assert tracker.should_notify() is False
    print("[quiet-pending] pending state does not notify")


def test_waiting_on_dependency_does_not_notify():
    tracker = LoopStateTracker()
    tracker.transition(
        LoopState.WAITING_ON_DEPENDENCY,
        blocker_code=BlockerCode.WAITING_ON_DEPENDENCY,
        reason="Upstream not done",
    )
    assert tracker.should_notify() is False
    print("[quiet-waiting] waiting_on_dependency does not notify")


def test_deterministic_redispatch_does_not_notify():
    tracker = LoopStateTracker()
    tracker.transition(
        LoopState.DETERMINISTIC_REDISPATCH_NEEDED,
        blocker_code=BlockerCode.DETERMINISTIC_REDISPATCH_NEEDED,
        reason="Will retry",
    )
    assert tracker.should_notify() is False
    print("[quiet-redispatch] deterministic_redispatch_needed does not notify")


def test_merge_ready_always_notifies():
    tracker = LoopStateTracker()
    t = tracker.transition(
        LoopState.MERGE_READY,
        blocker_code=BlockerCode.MERGE_READY,
        reason="Approved",
    )
    assert t is not None
    assert tracker.should_notify() is True
    print("[merge_ready] merge_ready notifies")


def test_blocked_first_occurrence_emits():
    classifier = BlockerClassifier()
    manager = NotificationManager()

    blocker = classifier.classify(
        "worktree_missing",
        beads_id="bd-test-1",
        wave_id="wave-test",
    )
    notification = manager.create_notification(blocker)
    assert notification is not None, "First blocked occurrence should emit"
    assert notification.notification_type == "blocked"
    assert notification.beads_id == "bd-test-1"
    assert (
        "worktree" in notification.next_action.lower()
        or "bootstrap" in notification.next_action.lower()
    )
    print("[first-blocked] first blocked occurrence emits notification")


def test_blocked_unchanged_suppressed():
    classifier = BlockerClassifier()
    manager = NotificationManager()

    blocker1 = classifier.classify(
        "worktree_missing",
        beads_id="bd-test-2",
        wave_id="wave-test",
    )
    note1 = manager.create_notification(blocker1)
    assert note1 is not None

    blocker2 = classifier.classify(
        "worktree_missing",
        beads_id="bd-test-2",
        wave_id="wave-test",
    )
    note2 = manager.create_notification(blocker2)
    assert note2 is None, "Unchanged repeat should be suppressed"
    print("[suppress-unchanged] unchanged blocker is suppressed")


def test_different_blocker_emits_after_suppression():
    classifier = BlockerClassifier()
    manager = NotificationManager()

    classifier.classify("worktree_missing", beads_id="bd-test-3", wave_id="wave-test")
    manager.create_notification(
        classifier.classify(
            "worktree_missing", beads_id="bd-test-3", wave_id="wave-test"
        )
    )

    new_blocker = classifier.classify(
        "opencode_rate_limited",
        beads_id="bd-test-3",
        wave_id="wave-test",
    )
    note = manager.create_notification(new_blocker)
    assert note is not None, "Different blocker should emit after suppression"
    print("[different-blocker] different blocker emits after suppression")


def test_needs_decision_emits():
    classifier = BlockerClassifier()
    manager = NotificationManager()

    blocker = classifier.classify(
        "max_attempts_exceeded",
        beads_id="bd-test-4",
        wave_id="wave-test",
    )
    notification = manager.create_notification(blocker)
    assert notification is not None, "needs_decision should emit"
    assert notification.notification_type == "needs_decision"
    print("[needs_decision] needs_decision emits notification")


def test_needs_decision_payload_with_attempt_context():
    classifier = BlockerClassifier()
    manager = NotificationManager()

    blocker = classifier.classify(
        "max_attempts_exceeded",
        beads_id="bd-test-5",
        wave_id="wave-test",
        metadata={"failure_reason": "max_attempts_exceeded"},
    )
    notification = manager.create_notification(
        blocker,
        task_title="Fix auth lane",
        attempt=3,
        max_attempts=3,
    )
    assert notification is not None
    assert notification.attempt == 3
    assert notification.max_attempts == 3
    assert notification.task_title == "Fix auth lane"
    cli = notification.format_cli()
    assert "3/3" in cli
    assert "Fix auth lane" in cli
    print("[needs-decision-payload] needs_decision includes attempt context")


def test_merge_ready_handoff_includes_pr_artifacts():
    classifier = BlockerClassifier()
    manager = NotificationManager()

    blocker = classifier.classify(
        None,
        beads_id="bd-test-6",
        wave_id="wave-test",
        has_pr_artifacts=True,
        checks_passing=True,
    )
    notification = manager.create_notification(
        blocker,
        pr_url="https://github.com/stars-end/agent-skills/pull/123",
        pr_head_sha="a" * 40,
        task_title="Implement feature X",
    )
    assert notification is not None
    assert notification.notification_type == "merge_ready"
    assert notification.pr_url == "https://github.com/stars-end/agent-skills/pull/123"
    assert notification.pr_head_sha == "a" * 40
    assert notification.task_title == "Implement feature X"

    cli = notification.format_cli()
    assert "MERGE_READY" in cli
    assert "Implement feature X" in cli
    assert "bd-test-6" in cli
    assert "pull/123" in cli
    assert "Next:" in cli
    print(
        "[merge-ready-handoff] merge_ready includes PR URL, SHA, task title, beads_id"
    )


def test_cli_shows_beads_id_alongside_task_title():
    classifier = BlockerClassifier()
    manager = NotificationManager()

    blocker = classifier.classify(
        None,
        beads_id="bd-5w5o.37.1",
        wave_id="wave-test",
        has_pr_artifacts=True,
        checks_passing=True,
    )
    notification = manager.create_notification(
        blocker,
        pr_url="https://github.com/stars-end/agent-skills/pull/999",
        pr_head_sha="c" * 40,
        task_title="Fix notification CLI handoff",
    )
    assert notification is not None
    cli = notification.format_cli()
    assert "bd-5w5o.37.1" in cli, "beads_id must be visible in CLI output"
    assert "Fix notification CLI handoff" in cli, (
        "task_title must be visible in CLI output"
    )
    print(
        "[beads-id-visibility] CLI shows beads_id alongside task_title for dx-loop takeover/resume"
    )


def test_merge_ready_operator_payload_is_complete():
    classifier = BlockerClassifier()
    manager = NotificationManager()

    blocker = classifier.classify(
        None,
        beads_id="bd-test-7",
        wave_id="wave-prod",
        has_pr_artifacts=True,
        checks_passing=True,
    )
    notification = manager.create_notification(
        blocker,
        pr_url="https://github.com/stars-end/agent-skills/pull/456",
        pr_head_sha="b" * 40,
        task_title="Harden notification policy",
    )
    assert notification is not None

    payload = notification.to_operator_payload()
    assert payload["operator_handoff"] is True
    assert payload["notification_type"] == "merge_ready"
    assert payload["beads_id"] == "bd-test-7"
    assert payload["wave_id"] == "wave-prod"
    assert payload["pr_url"] == "https://github.com/stars-end/agent-skills/pull/456"
    assert payload["pr_head_sha"] == "b" * 40
    assert payload["task_title"] == "Harden notification policy"
    assert "next_action" in payload
    print("[operator-payload] structured operator payload is complete")


def test_blocked_cli_shows_attempt_progress():
    classifier = BlockerClassifier()
    manager = NotificationManager()

    blocker = classifier.classify(
        "opencode_rate_limited",
        beads_id="bd-test-8",
        wave_id="wave-test",
    )
    notification = manager.create_notification(
        blocker,
        task_title="Retry task",
        attempt=2,
        max_attempts=3,
    )
    assert notification is not None
    cli = notification.format_cli()
    assert "2/3" in cli
    assert "BLOCKED" in cli
    print("[blocked-attempt] blocked CLI shows attempt progress")


def test_review_blocked_emits():
    classifier = BlockerClassifier()
    manager = NotificationManager()

    blocker = classifier.classify_review_blocked(
        beads_id="bd-test-9",
        wave_id="wave-test",
        review_findings=["Missing test coverage", "Contract drift"],
    )
    notification = manager.create_notification(blocker)
    assert notification is not None
    assert notification.notification_type == "blocked"
    assert notification.blocker_code == BlockerCode.REVIEW_BLOCKED
    print("[review-blocked] review_blocked emits notification")


def test_suppression_survives_restart():
    classifier1 = BlockerClassifier()
    manager1 = NotificationManager()

    blocker1 = classifier1.classify(
        "preflight_failed",
        beads_id="bd-restart-1",
        wave_id="wave-test",
    )
    note1 = manager1.create_notification(blocker1)
    assert note1 is not None

    classifier2 = BlockerClassifier.from_dict(classifier1.to_dict())
    manager2 = NotificationManager.from_dict(manager1.to_dict())

    blocker2 = classifier2.classify(
        "preflight_failed",
        beads_id="bd-restart-1",
        wave_id="wave-test",
    )
    note2 = manager2.create_notification(blocker2)

    assert blocker2.is_unchanged
    assert note2 is None
    print("[restart-suppression] unchanged-blocker suppression survives restart")


def test_tracker_last_emitted_blocker_persists():
    tracker1 = LoopStateTracker()
    tracker1.transition(
        LoopState.RUN_BLOCKED,
        blocker_code=BlockerCode.RUN_BLOCKED,
        reason="First block",
    )

    data = tracker1.to_dict()
    assert data["last_emitted_blocker"] == "run_blocked"

    tracker2 = LoopStateTracker.from_dict(data)
    assert tracker2.last_emitted_blocker == BlockerCode.RUN_BLOCKED
    assert tracker2.current_state == LoopState.RUN_BLOCKED

    t = tracker2.transition(
        LoopState.RUN_BLOCKED,
        blocker_code=BlockerCode.RUN_BLOCKED,
        reason="Same block again",
    )
    assert t is None, (
        "Should be suppressed after restart because last_emitted_blocker is restored"
    )
    print("[tracker-persist] last_emitted_blocker survives save/load")


def test_healthy_and_pending_never_create_notification():
    classifier = BlockerClassifier()
    manager = NotificationManager()

    healthy_blocker = BlockerState(
        code=BlockerCode.DETERMINISTIC_REDISPATCH_NEEDED,
        severity=BlockerSeverity.WARNING,
        message="Will auto-retry",
        beads_id="bd-quiet-1",
        wave_id="wave-test",
    )
    assert manager.create_notification(healthy_blocker) is None

    pending_blocker = BlockerState(
        code=BlockerCode.WAITING_ON_DEPENDENCY,
        severity=BlockerSeverity.INFO,
        message="Waiting",
        beads_id="bd-quiet-2",
        wave_id="wave-test",
    )
    assert manager.create_notification(pending_blocker) is None
    print("[quiet-manager] NotificationManager rejects healthy and pending")


def test_needs_decision_next_action_describes_exhaustion():
    classifier = BlockerClassifier()
    manager = NotificationManager()

    blocker = classifier.classify(
        "max_attempts_exceeded",
        beads_id="bd-exhaust",
        wave_id="wave-test",
        metadata={"failure_reason": "max_attempts_exceeded"},
    )
    notification = manager.create_notification(blocker)
    assert notification is not None
    assert (
        "exhausted" in notification.next_action.lower()
        or "retry" in notification.next_action.lower()
    )
    print("[needs-decision-action] needs_decision next action describes exhaustion")


if __name__ == "__main__":
    test_healthy_state_does_not_notify()
    test_pending_state_does_not_notify()
    test_waiting_on_dependency_does_not_notify()
    test_deterministic_redispatch_does_not_notify()
    test_merge_ready_always_notifies()
    test_blocked_first_occurrence_emits()
    test_blocked_unchanged_suppressed()
    test_different_blocker_emits_after_suppression()
    test_needs_decision_emits()
    test_needs_decision_payload_with_attempt_context()
    test_merge_ready_handoff_includes_pr_artifacts()
    test_cli_shows_beads_id_alongside_task_title()
    test_merge_ready_operator_payload_is_complete()
    test_blocked_cli_shows_attempt_progress()
    test_review_blocked_emits()
    test_suppression_survives_restart()
    test_tracker_last_emitted_blocker_persists()
    test_healthy_and_pending_never_create_notification()
    test_needs_decision_next_action_describes_exhaustion()
    print("\nAll notification policy tests passed!")
