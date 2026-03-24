"""
dx-loop low-noise operator notification policy

Emits interrupts only for:
- merge_ready: Ready for human merge
- blocked: Execution blocked (kickoff_env, run, review)
- needs_decision: Requires human decision

Suppresses:
- Unchanged blockers (same state as last notification)
- Healthy/pending states (no interrupt needed)

Every emitted interrupt includes a concise operator handoff payload:
- what task/wave is affected
- why the operator is being interrupted
- what the next action is
"""

from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List
import json
from .blocker import BlockerState, BlockerCode


@dataclass
class Notification:
    """Represents an operator notification with handoff context"""

    notification_type: str
    blocker_code: BlockerCode
    message: str
    beads_id: Optional[str] = None
    wave_id: Optional[str] = None
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        )
    )
    next_action: str = ""
    metadata: Dict[str, Any] = field(default_factory=dict)

    pr_url: Optional[str] = None
    pr_head_sha: Optional[str] = None
    task_title: Optional[str] = None
    attempt: Optional[int] = None
    max_attempts: Optional[int] = None
    provider: Optional[str] = None
    phase: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        d: Dict[str, Any] = {
            "notification_type": self.notification_type,
            "blocker_code": self.blocker_code.value,
            "message": self.message,
            "beads_id": self.beads_id,
            "wave_id": self.wave_id,
            "timestamp": self.timestamp,
            "next_action": self.next_action,
        }
        if self.pr_url:
            d["pr_url"] = self.pr_url
        if self.pr_head_sha:
            d["pr_head_sha"] = self.pr_head_sha
        if self.task_title:
            d["task_title"] = self.task_title
        if self.attempt is not None:
            d["attempt"] = self.attempt
        if self.max_attempts is not None:
            d["max_attempts"] = self.max_attempts
        if self.metadata:
            d["metadata"] = self.metadata
        if self.provider:
            d["provider"] = self.provider
        if self.phase:
            d["phase"] = self.phase
        return d

    def to_operator_payload(self) -> Dict[str, Any]:
        """Structured handoff payload for machine consumption."""
        payload = self.to_dict()
        payload["operator_handoff"] = True
        return payload

    def format_cli(self) -> str:
        lines = [f"[{self.notification_type.upper()}] {self.message}"]
        if self.beads_id:
            label = self.task_title or self.beads_id
            lines.append(f"  Task: {label}")
        if self.provider or self.phase:
            ctx_parts = []
            if self.provider:
                ctx_parts.append(f"provider={self.provider}")
            if self.phase:
                ctx_parts.append(f"phase={self.phase}")
            lines.append(f"  Context: {' '.join(ctx_parts)}")
        if self.notification_type == "merge_ready":
            if self.pr_url:
                lines.append(f"  PR: {self.pr_url}")
            if self.pr_head_sha:
                lines.append(f"  SHA: {self.pr_head_sha}")
        if self.attempt is not None and self.max_attempts is not None:
            lines.append(f"  Attempt: {self.attempt}/{self.max_attempts}")
        if self.next_action:
            lines.append(f"  Next: {self.next_action}")
        return "\n".join(lines)


class NotificationManager:
    """
    Manages low-noise operator notifications

    Only emits notifications for actionable states:
    - merge_ready (ready for human merge)
    - blocked (execution blocked)
    - needs_decision (requires human input)

    Suppresses noise from unchanged blockers and healthy states.

    FIX for P1: Added serialization for last_notification_hash to survive restart.
    bd-5w5o.10: Enriched handoff payloads with PR artifacts and triage context.
    """

    def __init__(self, slack_webhook_url: Optional[str] = None):
        self.slack_webhook_url = slack_webhook_url
        self.notifications: List[Notification] = []
        self.last_notification_hash: Dict[str, str] = {}

    def to_dict(self) -> Dict[str, Any]:
        return {
            "last_notification_hash": dict(self.last_notification_hash),
        }

    @classmethod
    def from_dict(
        cls, data: Dict[str, Any], slack_webhook_url: Optional[str] = None
    ) -> "NotificationManager":
        manager = cls(slack_webhook_url=slack_webhook_url)
        if "last_notification_hash" in data:
            manager.last_notification_hash = dict(data["last_notification_hash"])
        return manager

    def should_notify(self, blocker: BlockerState) -> bool:
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
            if blocker.beads_id:
                current_hash = blocker.compute_hash()
                last_hash = self.last_notification_hash.get(blocker.beads_id)
                if current_hash == last_hash:
                    return False
            return True

        return False

    def create_notification(
        self,
        blocker: BlockerState,
        pr_url: Optional[str] = None,
        pr_head_sha: Optional[str] = None,
        task_title: Optional[str] = None,
        attempt: Optional[int] = None,
        max_attempts: Optional[int] = None,
        provider: Optional[str] = None,
        phase: Optional[str] = None,
    ) -> Optional[Notification]:
        if not self.should_notify(blocker):
            return None

        notification_type = self._get_notification_type(blocker.code)
        next_action = self._get_next_action(blocker.code, blocker.metadata)

        notification = Notification(
            notification_type=notification_type,
            blocker_code=blocker.code,
            message=blocker.message,
            beads_id=blocker.beads_id,
            wave_id=blocker.wave_id,
            next_action=next_action,
            metadata=blocker.metadata,
            pr_url=pr_url,
            pr_head_sha=pr_head_sha,
            task_title=task_title,
            attempt=attempt,
            max_attempts=max_attempts,
            provider=provider,
            phase=phase,
        )

        if blocker.beads_id:
            self.last_notification_hash[blocker.beads_id] = blocker.compute_hash()

        self.notifications.append(notification)
        return notification

    def _get_notification_type(self, blocker_code: BlockerCode) -> str:
        if blocker_code == BlockerCode.MERGE_READY:
            return "merge_ready"
        elif blocker_code in (
            BlockerCode.KICKOFF_ENV_BLOCKED,
            BlockerCode.RUN_BLOCKED,
            BlockerCode.REVIEW_BLOCKED,
        ):
            return "blocked"
        elif blocker_code == BlockerCode.NEEDS_DECISION:
            return "needs_decision"
        else:
            return "info"

    def _get_next_action(
        self, blocker_code: BlockerCode, metadata: Optional[Dict[str, Any]] = None
    ) -> str:
        action_map = {
            BlockerCode.MERGE_READY: "Review and merge PR via GitHub UI",
            BlockerCode.KICKOFF_ENV_BLOCKED: "Fix bootstrap environment (worktree/host/Beads)",
            BlockerCode.RUN_BLOCKED: "Wait for capacity or switch provider",
            BlockerCode.REVIEW_BLOCKED: "Address review findings and re-submit",
            BlockerCode.NEEDS_DECISION: "Manual intervention required - check logs",
        }
        default = action_map.get(blocker_code, "Review logs")

        if blocker_code == BlockerCode.NEEDS_DECISION and metadata:
            reason = metadata.get("failure_reason", "")
            if reason == "max_attempts_exceeded":
                return "All retries exhausted - inspect logs and decide: retry, skip, or takeover"
            if reason == "retry_chain_exhausted":
                return "Revision chain exhausted - inspect logs and decide: accept or takeover"

        return default

    def emit_cli(self, notification: Notification):
        print(notification.format_cli())

    def emit_slack(self, notification: Notification) -> bool:
        if not self.slack_webhook_url:
            return False

        try:
            import urllib.request

            payload = {
                "text": notification.format_cli(),
                "mrkdwn": True,
            }

            data = json.dumps(payload).encode("utf-8")
            req = urllib.request.Request(
                self.slack_webhook_url,
                data=data,
                headers={"Content-Type": "application/json"},
            )

            with urllib.request.urlopen(req, timeout=10) as response:
                return response.status == 200

        except Exception:
            return False

    def get_recent_notifications(self, limit: int = 10) -> List[Notification]:
        return self.notifications[-limit:]
