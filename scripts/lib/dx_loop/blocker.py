"""
dx-loop blocker classification and unchanged-state suppression

Implements 6-blocker taxonomy with deterministic classification:
1. kickoff_env_blocked - Bootstrap/worktree/host gates failed
2. run_blocked - dx-runner execution blocked (not stalled)
3. review_blocked - Reviewer verdict blocked
4. deterministic_redispatch_needed - Stalled/timeout, safe to retry
5. needs_decision - Requires human decision
6. merge_ready - PR artifacts present, checks passing, ready for merge

Includes unchanged-blocker suppression to reduce noise.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Optional, Dict, Any, List
import json
from .state_machine import BlockerCode, LoopState


class BlockerSeverity(str, Enum):
    """Blocker severity levels"""
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


@dataclass
class BlockerState:
    """
    Represents a classified blocker with metadata
    
    Includes unchanged detection to enable suppression.
    """
    code: BlockerCode
    severity: BlockerSeverity
    message: str
    beads_id: Optional[str] = None
    wave_id: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    
    # Unchanged detection
    previous_hash: Optional[str] = None
    is_unchanged: bool = False
    
    def compute_hash(self) -> str:
        """Compute hash for unchanged detection"""
        import hashlib
        content = f"{self.code.value}:{self.severity.value}:{self.message}:{self.beads_id}"
        return hashlib.sha256(content.encode()).hexdigest()[:16]
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "code": self.code.value,
            "severity": self.severity.value,
            "message": self.message,
            "beads_id": self.beads_id,
            "wave_id": self.wave_id,
            "metadata": self.metadata,
            "timestamp": self.timestamp,
            "is_unchanged": self.is_unchanged,
        }


class BlockerClassifier:
    """
    Classifies blocker states from dx-runner outcomes
    
    Maps dx-runner reason_codes to dx-loop blocker taxonomy with
    unchanged detection for noise suppression.
    """

    # Mapping from dx-runner reason_codes to blocker taxonomy
    RUNNER_REASON_MAP = {
        # Bootstrap/worktree/host gates
        "worktree_missing": BlockerCode.KICKOFF_ENV_BLOCKED,
        "beads_cwd_gate_failed": BlockerCode.KICKOFF_ENV_BLOCKED,
        "preflight_failed": BlockerCode.KICKOFF_ENV_BLOCKED,
        "auth_resolution_failed": BlockerCode.KICKOFF_ENV_BLOCKED,
        "railway_auth_missing": BlockerCode.KICKOFF_ENV_BLOCKED,
        "railway_cli_missing": BlockerCode.KICKOFF_ENV_BLOCKED,
        
        # Run blocked (not stalled)
        "provider_concurrency_cap_exceeded": BlockerCode.RUN_BLOCKED,
        "opencode_rate_limited": BlockerCode.RUN_BLOCKED,
        "gemini_capacity_exhausted": BlockerCode.RUN_BLOCKED,
        "execution_mode_unsupported": BlockerCode.RUN_BLOCKED,
        
        # Deterministic redispatch (stalled/timeout)
        "stalled_no_progress": BlockerCode.DETERMINISTIC_REDISPATCH_NEEDED,
        "no_op": BlockerCode.DETERMINISTIC_REDISPATCH_NEEDED,
        "monitor_no_rc_file": BlockerCode.DETERMINISTIC_REDISPATCH_NEEDED,
        "process_timeout": BlockerCode.DETERMINISTIC_REDISPATCH_NEEDED,
        
        # Needs decision
        "max_attempts_exceeded": BlockerCode.NEEDS_DECISION,
        "retry_chain_exhausted": BlockerCode.NEEDS_DECISION,
        "manual_stop": BlockerCode.NEEDS_DECISION,
    }

    def __init__(self):
        self.previous_blockers: Dict[str, BlockerState] = {}  # keyed by beads_id

    def classify(
        self,
        runner_reason_code: Optional[str],
        beads_id: Optional[str] = None,
        wave_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
        has_pr_artifacts: bool = False,
        checks_passing: bool = False,
    ) -> BlockerState:
        """
        Classify blocker from dx-runner outcome
        
        Args:
            runner_reason_code: Reason code from dx-runner check/report
            beads_id: Beads issue ID
            wave_id: Wave ID
            metadata: Additional metadata
            has_pr_artifacts: Whether PR_URL and PR_HEAD_SHA are present
            checks_passing: Whether CI checks are passing
        
        Returns:
            BlockerState with unchanged detection
        """
        # Check merge-ready first
        if has_pr_artifacts and checks_passing:
            blocker = BlockerState(
                code=BlockerCode.MERGE_READY,
                severity=BlockerSeverity.INFO,
                message="PR artifacts present and checks passing, ready for merge",
                beads_id=beads_id,
                wave_id=wave_id,
                metadata=metadata or {},
            )
        elif runner_reason_code:
            blocker_code = self.RUNNER_REASON_MAP.get(
                runner_reason_code, BlockerCode.NEEDS_DECISION
            )
            severity = self._get_severity(blocker_code)
            blocker = BlockerState(
                code=blocker_code,
                severity=severity,
                message=f"Runner reason: {runner_reason_code}",
                beads_id=beads_id,
                wave_id=wave_id,
                metadata=metadata or {},
            )
        else:
            # Default to needs_decision for unknown states
            blocker = BlockerState(
                code=BlockerCode.NEEDS_DECISION,
                severity=BlockerSeverity.WARNING,
                message="Unknown blocker state",
                beads_id=beads_id,
                wave_id=wave_id,
                metadata=metadata or {},
            )
        
        # Unchanged detection
        if beads_id and beads_id in self.previous_blockers:
            prev = self.previous_blockers[beads_id]
            blocker.previous_hash = prev.compute_hash()
            if blocker.compute_hash() == blocker.previous_hash:
                blocker.is_unchanged = True
        
        # Cache for next comparison
        if beads_id:
            self.previous_blockers[beads_id] = blocker
        
        return blocker

    def classify_review_blocked(
        self,
        beads_id: Optional[str] = None,
        wave_id: Optional[str] = None,
        review_findings: Optional[List[str]] = None,
    ) -> BlockerState:
        """Classify review-blocked state"""
        blocker = BlockerState(
            code=BlockerCode.REVIEW_BLOCKED,
            severity=BlockerSeverity.WARNING,
            message="Review returned BLOCKED verdict",
            beads_id=beads_id,
            wave_id=wave_id,
            metadata={"findings": review_findings or []},
        )
        
        # Unchanged detection
        if beads_id and beads_id in self.previous_blockers:
            prev = self.previous_blockers[beads_id]
            blocker.previous_hash = prev.compute_hash()
            if blocker.compute_hash() == blocker.previous_hash:
                blocker.is_unchanged = True
        
        if beads_id:
            self.previous_blockers[beads_id] = blocker
        
        return blocker

    def _get_severity(self, blocker_code: BlockerCode) -> BlockerSeverity:
        """Map blocker code to severity"""
        severity_map = {
            BlockerCode.MERGE_READY: BlockerSeverity.INFO,
            BlockerCode.DETERMINISTIC_REDISPATCH_NEEDED: BlockerSeverity.WARNING,
            BlockerCode.KICKOFF_ENV_BLOCKED: BlockerSeverity.ERROR,
            BlockerCode.RUN_BLOCKED: BlockerSeverity.ERROR,
            BlockerCode.REVIEW_BLOCKED: BlockerSeverity.ERROR,
            BlockerCode.NEEDS_DECISION: BlockerSeverity.CRITICAL,
        }
        return severity_map.get(blocker_code, BlockerSeverity.WARNING)

    def should_notify(self, blocker: BlockerState) -> bool:
        """
        Determine if operator notification should be sent
        
        Notify for: merge_ready, blocked states, needs_decision
        Suppress: unchanged blockers
        """
        if blocker.is_unchanged:
            return False
        
        if blocker.code == BlockerCode.MERGE_READY:
            return True
        
        if blocker.code in (
            BlockerCode.KICKOFF_ENV_BLOCKED,
            BlockerCode.RUN_BLOCKED,
            BlockerCode.REVIEW_BLOCKED,
            BlockerCode.NEEDS_DECISION,
        ):
            return True
        
        return False

    def get_notification_payload(self, blocker: BlockerState) -> Optional[Dict[str, Any]]:
        """Get notification payload if should_notify() is True"""
        if not self.should_notify(blocker):
            return None
        
        return {
            "blocker_code": blocker.code.value,
            "severity": blocker.severity.value,
            "message": blocker.message,
            "beads_id": blocker.beads_id,
            "wave_id": blocker.wave_id,
            "timestamp": blocker.timestamp,
            "is_unchanged": blocker.is_unchanged,
            "next_action": self._get_next_action(blocker.code),
        }

    def _get_next_action(self, blocker_code: BlockerCode) -> str:
        """Map blocker code to suggested next action"""
        action_map = {
            BlockerCode.MERGE_READY: "human_merge_approval",
            BlockerCode.KICKOFF_ENV_BLOCKED: "fix_bootstrap_environment",
            BlockerCode.RUN_BLOCKED: "wait_or_switch_provider",
            BlockerCode.REVIEW_BLOCKED: "address_review_findings",
            BlockerCode.DETERMINISTIC_REDISPATCH_NEEDED: "automatic_redispatch",
            BlockerCode.NEEDS_DECISION: "human_intervention_required",
        }
        return action_map.get(blocker_code, "review_logs")
