"""
dx-loop baton semantics - Implementer/Reviewer cycle

Reuses Ralph's implementer/reviewer baton pattern with:
- Explicit IMPLEMENT → REVIEW phases
- Structured verdicts (APPROVED, REVISION_REQUIRED, BLOCKED)
- Retry bounds and deterministic termination

Key differences from Ralph:
- Uses dx-runner substrate instead of curl/session
- PR artifact requirement for completion
- Explicit blocker classification
"""

from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Optional, Dict, Any, List
import json


class BatonPhase(str, Enum):
    """Baton phases for implement/review cycle"""

    IDLE = "idle"
    IMPLEMENT = "implement"
    REVIEW = "review"
    MANUAL_TAKEOVER = "manual_takeover"
    COMPLETE = "complete"
    FAILED = "failed"


class ReviewVerdict(str, Enum):
    """Structured reviewer verdicts"""

    APPROVED = "APPROVED"
    REVISION_REQUIRED = "REVISION_REQUIRED"
    BLOCKED = "BLOCKED"


@dataclass
class BatonState:
    """
    Tracks baton state for a single Beads item

    Reuses Ralph's max_attempts pattern and phase tracking,
    but adds PR artifact requirements for completion.
    """

    beads_id: str
    phase: BatonPhase = BatonPhase.IDLE
    attempt: int = 1
    max_attempts: int = 3
    verdict: Optional[ReviewVerdict] = None
    revision_count: int = 0
    max_revisions: int = 3

    # PR artifact contract (required for completion)
    pr_url: Optional[str] = None
    pr_head_sha: Optional[str] = None

    # Timing
    implement_started_at: Optional[str] = None
    implement_completed_at: Optional[str] = None
    review_started_at: Optional[str] = None
    review_completed_at: Optional[str] = None

    # dx-runner integration
    implement_run_id: Optional[str] = None
    review_run_id: Optional[str] = None

    # Metadata
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "beads_id": self.beads_id,
            "phase": self.phase.value,
            "attempt": self.attempt,
            "max_attempts": self.max_attempts,
            "verdict": self.verdict.value if self.verdict else None,
            "revision_count": self.revision_count,
            "max_revisions": self.max_revisions,
            "pr_url": self.pr_url,
            "pr_head_sha": self.pr_head_sha,
            "implement_started_at": self.implement_started_at,
            "implement_completed_at": self.implement_completed_at,
            "review_started_at": self.review_started_at,
            "review_completed_at": self.review_completed_at,
            "implement_run_id": self.implement_run_id,
            "review_run_id": self.review_run_id,
            "metadata": self.metadata,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "BatonState":
        state = cls(beads_id=data["beads_id"])
        if "phase" in data:
            state.phase = BatonPhase(data["phase"])
        if "attempt" in data:
            state.attempt = data["attempt"]
        if "max_attempts" in data:
            state.max_attempts = data["max_attempts"]
        if "verdict" in data and data["verdict"]:
            state.verdict = ReviewVerdict(data["verdict"])
        if "revision_count" in data:
            state.revision_count = data["revision_count"]
        if "max_revisions" in data:
            state.max_revisions = data["max_revisions"]
        if "pr_url" in data:
            state.pr_url = data["pr_url"]
        if "pr_head_sha" in data:
            state.pr_head_sha = data["pr_head_sha"]
        for field in [
            "implement_started_at",
            "implement_completed_at",
            "review_started_at",
            "review_completed_at",
            "implement_run_id",
            "review_run_id",
        ]:
            if field in data:
                setattr(state, field, data[field])
        if "metadata" in data:
            state.metadata = data["metadata"]
        return state


class BatonManager:
    """
    Manages baton lifecycle with deterministic termination

    Reuses Ralph's retry pattern:
    - Max attempts for implement phase
    - Max revisions for review failures
    - Deterministic termination when bounds exhausted

    Key delta from Ralph:
    - PR artifact requirement for APPROVED → COMPLETE transition
    - dx-runner run_id tracking instead of session management
    """

    def __init__(self, max_attempts: int = 3, max_revisions: int = 3):
        self.max_attempts = max_attempts
        self.max_revisions = max_revisions
        self.baton_states: Dict[str, BatonState] = {}

    def start_implement(
        self, beads_id: str, run_id: Optional[str] = None
    ) -> BatonState:
        """
        Start implement phase for a Beads item

        Reuses Ralph's attempt tracking pattern.
        """
        if beads_id not in self.baton_states:
            self.baton_states[beads_id] = BatonState(
                beads_id=beads_id,
                max_attempts=self.max_attempts,
                max_revisions=self.max_revisions,
            )

        state = self.baton_states[beads_id]
        state.phase = BatonPhase.IMPLEMENT
        state.implement_started_at = datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
        state.implement_run_id = run_id
        state.metadata.pop("last_retry_reason", None)

        return state

    def record_implement_retry(
        self, beads_id: str, failure_reason: Optional[str] = None
    ) -> BatonState:
        """
        Record a failed implement attempt that should be retried on a later cadence.
        """
        state = self.baton_states.get(beads_id)
        if not state:
            raise ValueError(f"No baton state for {beads_id}")

        state.attempt += 1
        if failure_reason:
            state.metadata["last_retry_reason"] = failure_reason

        if state.attempt > state.max_attempts:
            state.phase = BatonPhase.FAILED
            state.metadata["failure_reason"] = "max_attempts_exceeded"
        else:
            state.phase = BatonPhase.IMPLEMENT
            state.implement_started_at = None
            state.implement_run_id = None

        return state

    def complete_implement(
        self,
        beads_id: str,
        pr_url: Optional[str] = None,
        pr_head_sha: Optional[str] = None,
        run_id: Optional[str] = None,
    ) -> BatonState:
        """
        Complete implement phase and transition to review

        Key delta from Ralph: PR artifacts are captured here
        but not yet required until review approval.
        """
        state = self.baton_states.get(beads_id)
        if not state:
            raise ValueError(f"No baton state for {beads_id}")

        state.phase = BatonPhase.REVIEW
        state.implement_completed_at = datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )

        # Capture PR artifacts (may be None if implementer didn't create PR)
        if pr_url:
            state.pr_url = pr_url
        if pr_head_sha:
            state.pr_head_sha = pr_head_sha

        return state

    def start_review(self, beads_id: str, run_id: Optional[str] = None) -> BatonState:
        """Start review phase"""
        state = self.baton_states.get(beads_id)
        if not state:
            raise ValueError(f"No baton state for {beads_id}")

        if state.phase != BatonPhase.REVIEW:
            raise ValueError(f"Cannot start review from phase {state.phase.value}")

        state.review_started_at = datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
        state.review_run_id = run_id

        return state

    def complete_review(
        self,
        beads_id: str,
        verdict: ReviewVerdict,
        pr_url: Optional[str] = None,
        pr_head_sha: Optional[str] = None,
    ) -> BatonState:
        """
        Complete review phase with verdict

        Reuses Ralph's verdict handling with additional PR artifact enforcement:
        - APPROVED requires pr_url and pr_head_sha
        - REVISION_REQUIRED increments revision_count
        - BLOCKED transitions to FAILED after bounds check
        """
        state = self.baton_states.get(beads_id)
        if not state:
            raise ValueError(f"No baton state for {beads_id}")

        state.verdict = verdict
        state.review_completed_at = datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )

        # Update PR artifacts if provided
        if pr_url:
            state.pr_url = pr_url
        if pr_head_sha:
            state.pr_head_sha = pr_head_sha

        if verdict == ReviewVerdict.APPROVED:
            # KEY DELTA: Require PR artifacts for completion
            if not state.pr_url or not state.pr_head_sha:
                state.phase = BatonPhase.FAILED
                state.metadata["failure_reason"] = "missing_pr_artifacts"
                return state

            state.phase = BatonPhase.COMPLETE

        elif verdict == ReviewVerdict.REVISION_REQUIRED:
            state.revision_count += 1
            if state.revision_count >= state.max_revisions:
                state.phase = BatonPhase.FAILED
                state.metadata["failure_reason"] = "max_revisions_exceeded"
            else:
                # Transition back to implement for revision
                state.phase = BatonPhase.IMPLEMENT
                state.attempt += 1
                if state.attempt > state.max_attempts:
                    state.phase = BatonPhase.FAILED
                    state.metadata["failure_reason"] = "max_attempts_exceeded"

        elif verdict == ReviewVerdict.BLOCKED:
            state.phase = BatonPhase.FAILED
            state.metadata["failure_reason"] = "review_blocked"

        return state

    def get_state(self, beads_id: str) -> Optional[BatonState]:
        return self.baton_states.get(beads_id)

    def can_retry(self, beads_id: str) -> bool:
        """
        Check if retry is possible

        Reuses Ralph's deterministic termination logic.
        """
        state = self.baton_states.get(beads_id)
        if not state:
            return True

        if state.phase == BatonPhase.FAILED:
            return False

        return (
            state.attempt < state.max_attempts
            and state.revision_count < state.max_revisions
        )

    def get_next_action(self, beads_id: str) -> Optional[str]:
        """
        Determine next action for a Beads item

        Returns one of: start_implement, start_review, retry, blocked, complete,
        manual_takeover
        """
        state = self.baton_states.get(beads_id)
        if not state:
            return "start_implement"

        if state.phase == BatonPhase.COMPLETE:
            return "complete"

        if state.phase == BatonPhase.FAILED:
            return "blocked"

        if state.phase == BatonPhase.MANUAL_TAKEOVER:
            return "manual_takeover"

        if state.phase == BatonPhase.IMPLEMENT:
            return "start_implement"

        if state.phase == BatonPhase.REVIEW:
            return "start_review"

        return None

    def start_manual_takeover(
        self,
        beads_id: str,
        pr_url: Optional[str] = None,
        pr_head_sha: Optional[str] = None,
        operator_note: Optional[str] = None,
    ) -> BatonState:
        """
        Transition a task to manual takeover.

        The operator takes over responsibility for this task outside the loop.
        Baton and scheduler are preserved so resume works cleanly.
        """
        if beads_id not in self.baton_states:
            self.baton_states[beads_id] = BatonState(
                beads_id=beads_id,
                max_attempts=self.max_attempts,
                max_revisions=self.max_revisions,
            )

        state = self.baton_states[beads_id]
        prev_phase = state.phase
        state.phase = BatonPhase.MANUAL_TAKEOVER
        state.metadata["takeover_at"] = datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
        state.metadata["takeover_from"] = prev_phase.value
        state.metadata["operator_note"] = operator_note or ""

        if pr_url:
            state.pr_url = pr_url
        if pr_head_sha:
            state.pr_head_sha = pr_head_sha

        return state

    def resume_from_takeover(
        self,
        beads_id: str,
    ) -> BatonState:
        """
        Resume automation after manual takeover.

        Restores the previous phase (IMPLEMENT or REVIEW) so the loop
        can continue dispatching and polling.
        """
        state = self.baton_states.get(beads_id)
        if not state:
            raise ValueError(f"No baton state for {beads_id}")

        if state.phase != BatonPhase.MANUAL_TAKEOVER:
            raise ValueError(
                f"Cannot resume from {state.phase.value}, expected manual_takeover"
            )

        prev_phase = state.metadata.get("takeover_from", "implement")
        state.phase = BatonPhase(prev_phase)
        state.metadata["resumed_at"] = datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
        return state
