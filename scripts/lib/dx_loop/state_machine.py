"""
dx-loop state machine with blocker taxonomy

Implements the loop state model:
- pending, in_progress_healthy, deterministic_redispatch_needed
- kickoff_env_blocked, run_blocked, review_blocked, needs_decision, merge_ready

With unchanged-blocker suppression to reduce operator noise.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Optional, Dict, Any
import json


class BlockerCode(str, Enum):
    """Blocker taxonomy for dx-loop classification"""
    KICKOFF_ENV_BLOCKED = "kickoff_env_blocked"
    RUN_BLOCKED = "run_blocked"
    REVIEW_BLOCKED = "review_blocked"
    WAITING_ON_DEPENDENCY = "waiting_on_dependency"
    DETERMINISTIC_REDISPATCH_NEEDED = "deterministic_redispatch_needed"
    NEEDS_DECISION = "needs_decision"
    MERGE_READY = "merge_ready"
    UNCHANGED = "unchanged"  # Suppression marker


class LoopState(str, Enum):
    """dx-loop state model"""
    PENDING = "pending"
    IN_PROGRESS_HEALTHY = "in_progress_healthy"
    WAITING_ON_DEPENDENCY = "waiting_on_dependency"
    DETERMINISTIC_REDISPATCH_NEEDED = "deterministic_redispatch_needed"
    KICKOFF_ENV_BLOCKED = "kickoff_env_blocked"
    RUN_BLOCKED = "run_blocked"
    REVIEW_BLOCKED = "review_blocked"
    NEEDS_DECISION = "needs_decision"
    MERGE_READY = "merge_ready"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass
class StateTransition:
    """Represents a state transition with blocker metadata"""
    from_state: LoopState
    to_state: LoopState
    blocker_code: Optional[BlockerCode]
    reason: str
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "from_state": self.from_state.value,
            "to_state": self.to_state.value,
            "blocker_code": self.blocker_code.value if self.blocker_code else None,
            "reason": self.reason,
            "timestamp": self.timestamp,
            "metadata": self.metadata,
        }


@dataclass
class LoopStateTracker:
    """
    Tracks loop state with unchanged-blocker suppression
    
    Only emits blocker notifications when state materially changes,
    preventing noise from repeated identical states.
    """
    current_state: LoopState = LoopState.PENDING
    current_blocker: Optional[BlockerCode] = None
    last_blocker: Optional[BlockerCode] = None
    last_emitted_blocker: Optional[BlockerCode] = None
    transition_history: list = field(default_factory=list)
    unchanged_count: int = 0
    max_unchanged_before_log: int = 10

    def transition(
        self,
        new_state: LoopState,
        blocker_code: Optional[BlockerCode] = None,
        reason: str = "",
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Optional[StateTransition]:
        """
        Attempt state transition with unchanged suppression
        
        FIX for P1: Emit on FIRST occurrence, suppress only on REPEATED unchanged.
        
        Returns:
            StateTransition if emitted (not suppressed), None if suppressed
        """
        old_state = self.current_state
        old_blocker = self.current_blocker

        # Check if this is an unchanged blocker (AFTER first emission)
        if (
            new_state == old_state
            and blocker_code == old_blocker
            and blocker_code is not None
            and self.last_emitted_blocker == blocker_code  # Only suppress if already emitted
        ):
            self.unchanged_count += 1
            # Only emit every N unchanged occurrences
            if self.unchanged_count % self.max_unchanged_before_log != 0:
                return None
        else:
            self.unchanged_count = 0

        # Create transition
        transition = StateTransition(
            from_state=old_state,
            to_state=new_state,
            blocker_code=blocker_code,
            reason=reason,
            metadata=metadata or {},
        )

        # Update state
        self.current_state = new_state
        self.current_blocker = blocker_code
        if blocker_code:
            self.last_blocker = blocker_code
            # Mark as emitted AFTER first occurrence
            if self.last_emitted_blocker != blocker_code:
                self.last_emitted_blocker = blocker_code

        # Record transition
        self.transition_history.append(transition)

        return transition

    def should_notify(self) -> bool:
        """
        Determine if operator notification should be sent
        
        Only notify for: merge_ready, blocked states, needs_decision
        """
        if self.current_state == LoopState.MERGE_READY:
            return True
        if self.current_blocker in (
            BlockerCode.KICKOFF_ENV_BLOCKED,
            BlockerCode.RUN_BLOCKED,
            BlockerCode.REVIEW_BLOCKED,
            BlockerCode.NEEDS_DECISION,
        ):
            # Only notify if blocker changed or first occurrence
            return self.current_blocker != self.last_emitted_blocker
        return False

    def get_notification_payload(self) -> Optional[Dict[str, Any]]:
        """Get notification payload if should_notify() is True"""
        if not self.should_notify():
            return None

        return {
            "state": self.current_state.value,
            "blocker_code": self.current_blocker.value if self.current_blocker else None,
            "unchanged_count": self.unchanged_count,
            "last_transition": (
                self.transition_history[-1].to_dict() if self.transition_history else None
            ),
        }

    def to_dict(self) -> Dict[str, Any]:
        last_transition = (
            self.transition_history[-1].to_dict() if self.transition_history else None
        )
        return {
            "current_state": self.current_state.value,
            "current_blocker": self.current_blocker.value if self.current_blocker else None,
            "last_blocker": self.last_blocker.value if self.last_blocker else None,
            "unchanged_count": self.unchanged_count,
            "transition_count": len(self.transition_history),
            "last_transition": last_transition,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "LoopStateTracker":
        tracker = cls()
        if "current_state" in data:
            tracker.current_state = LoopState(data["current_state"])
        if "current_blocker" in data and data["current_blocker"]:
            tracker.current_blocker = BlockerCode(data["current_blocker"])
        if "last_blocker" in data and data["last_blocker"]:
            tracker.last_blocker = BlockerCode(data["last_blocker"])
        if "unchanged_count" in data:
            tracker.unchanged_count = data["unchanged_count"]
        return tracker


class LoopStateMachine:
    """
    State machine with deterministic transition rules
    
    Validates transitions against allowed paths and enforces
    blocker taxonomy consistency.
    """

    # Allowed transitions: {from_state: [allowed_to_states]}
    ALLOWED_TRANSITIONS = {
        LoopState.PENDING: [
            LoopState.IN_PROGRESS_HEALTHY,
            LoopState.WAITING_ON_DEPENDENCY,
            LoopState.KICKOFF_ENV_BLOCKED,
        ],
        LoopState.WAITING_ON_DEPENDENCY: [
            LoopState.IN_PROGRESS_HEALTHY,
            LoopState.COMPLETED,
            LoopState.NEEDS_DECISION,
        ],
        LoopState.IN_PROGRESS_HEALTHY: [
            LoopState.WAITING_ON_DEPENDENCY,
            LoopState.DETERMINISTIC_REDISPATCH_NEEDED,
            LoopState.RUN_BLOCKED,
            LoopState.REVIEW_BLOCKED,
            LoopState.MERGE_READY,
            LoopState.COMPLETED,
            LoopState.FAILED,
        ],
        LoopState.DETERMINISTIC_REDISPATCH_NEEDED: [
            LoopState.IN_PROGRESS_HEALTHY,
            LoopState.NEEDS_DECISION,
        ],
        LoopState.KICKOFF_ENV_BLOCKED: [
            LoopState.PENDING,
            LoopState.NEEDS_DECISION,
        ],
        LoopState.RUN_BLOCKED: [
            LoopState.IN_PROGRESS_HEALTHY,
            LoopState.DETERMINISTIC_REDISPATCH_NEEDED,
            LoopState.NEEDS_DECISION,
        ],
        LoopState.REVIEW_BLOCKED: [
            LoopState.IN_PROGRESS_HEALTHY,
            LoopState.NEEDS_DECISION,
        ],
        LoopState.NEEDS_DECISION: [
            LoopState.PENDING,
            LoopState.IN_PROGRESS_HEALTHY,
            LoopState.FAILED,
        ],
        LoopState.MERGE_READY: [
            LoopState.COMPLETED,
        ],
        LoopState.COMPLETED: [],
        LoopState.FAILED: [],
    }

    def __init__(self, tracker: Optional[LoopStateTracker] = None):
        self.tracker = tracker or LoopStateTracker()

    def can_transition(self, to_state: LoopState) -> bool:
        """Check if transition to target state is allowed"""
        allowed = self.ALLOWED_TRANSITIONS.get(self.tracker.current_state, [])
        return to_state in allowed

    def transition(
        self,
        to_state: LoopState,
        blocker_code: Optional[BlockerCode] = None,
        reason: str = "",
        metadata: Optional[Dict[str, Any]] = None,
        force: bool = False,
    ) -> Optional[StateTransition]:
        """
        Attempt transition with validation
        
        Args:
            to_state: Target state
            blocker_code: Optional blocker classification
            reason: Human-readable reason
            metadata: Additional metadata
            force: Skip validation (use with caution)
        
        Returns:
            StateTransition if valid and not suppressed, None otherwise
        
        Raises:
            ValueError: If transition invalid and force=False
        """
        if not force and not self.can_transition(to_state):
            allowed = self.ALLOWED_TRANSITIONS.get(self.tracker.current_state, [])
            raise ValueError(
                f"Invalid transition from {self.tracker.current_state.value} to {to_state.value}. "
                f"Allowed: {[s.value for s in allowed]}"
            )

        return self.tracker.transition(to_state, blocker_code, reason, metadata)

    def get_state(self) -> LoopState:
        return self.tracker.current_state

    def get_blocker(self) -> Optional[BlockerCode]:
        return self.tracker.current_blocker
