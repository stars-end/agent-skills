"""
dx-loop low-noise operator notification policy

Emits interrupts only for:
- merge_ready: Ready for human merge
- blocked: Execution blocked (kickoff_env, run, review)
- needs_decision: Requires human decision

Suppresses:
- Unchanged blockers (same state as last notification)
- Healthy/pending states (no interrupt needed)
"""

from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List
import json
from .blocker import BlockerState, BlockerCode


@dataclass
class Notification:
    """Represents an operator notification"""
    notification_type: str  # merge_ready, blocked, needs_decision
    blocker_code: BlockerCode
    message: str
    beads_id: Optional[str] = None
    wave_id: Optional[str] = None
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    next_action: str = ""
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "notification_type": self.notification_type,
            "blocker_code": self.blocker_code.value,
            "message": self.message,
            "beads_id": self.beads_id,
            "wave_id": self.wave_id,
            "timestamp": self.timestamp,
            "next_action": self.next_action,
            "metadata": self.metadata,
        }
    
    def format_cli(self) -> str:
        """Format notification for CLI output"""
        lines = [
            f"[{self.notification_type.upper()}] {self.message}",
            f"  Blocker: {self.blocker_code.value}",
        ]
        if self.beads_id:
            lines.append(f"  Beads: {self.beads_id}")
        if self.wave_id:
            lines.append(f"  Wave: {self.wave_id}")
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
    """
    
    def __init__(self, slack_webhook_url: Optional[str] = None):
        self.slack_webhook_url = slack_webhook_url
        self.notifications: List[Notification] = []
        self.last_notification_hash: Dict[str, str] = {}  # keyed by beads_id
    
    def should_notify(self, blocker: BlockerState) -> bool:
        """
        Determine if notification should be sent
        
        Notify for: merge_ready, blocked, needs_decision
        Suppress: unchanged blockers, healthy states
        """
        # Never notify for unchanged blockers
        if blocker.is_unchanged:
            return False
        
        # Only notify for actionable states
        if blocker.code == BlockerCode.MERGE_READY:
            return True
        
        if blocker.code in (
            BlockerCode.KICKOFF_ENV_BLOCKED,
            BlockerCode.RUN_BLOCKED,
            BlockerCode.REVIEW_BLOCKED,
            BlockerCode.NEEDS_DECISION,
        ):
            # Check if we already notified for this state
            if blocker.beads_id:
                current_hash = blocker.compute_hash()
                last_hash = self.last_notification_hash.get(blocker.beads_id)
                if current_hash == last_hash:
                    return False
            return True
        
        return False
    
    def create_notification(self, blocker: BlockerState) -> Optional[Notification]:
        """Create notification from blocker state if should_notify()"""
        if not self.should_notify(blocker):
            return None
        
        notification_type = self._get_notification_type(blocker.code)
        next_action = self._get_next_action(blocker.code)
        
        notification = Notification(
            notification_type=notification_type,
            blocker_code=blocker.code,
            message=blocker.message,
            beads_id=blocker.beads_id,
            wave_id=blocker.wave_id,
            next_action=next_action,
            metadata=blocker.metadata,
        )
        
        # Update hash to prevent duplicates
        if blocker.beads_id:
            self.last_notification_hash[blocker.beads_id] = blocker.compute_hash()
        
        self.notifications.append(notification)
        return notification
    
    def _get_notification_type(self, blocker_code: BlockerCode) -> str:
        """Map blocker code to notification type"""
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
    
    def _get_next_action(self, blocker_code: BlockerCode) -> str:
        """Map blocker code to next action"""
        action_map = {
            BlockerCode.MERGE_READY: "Review and merge PR via GitHub UI",
            BlockerCode.KICKOFF_ENV_BLOCKED: "Fix bootstrap environment (worktree/host/Beads)",
            BlockerCode.RUN_BLOCKED: "Wait for capacity or switch provider",
            BlockerCode.REVIEW_BLOCKED: "Address review findings and re-submit",
            BlockerCode.NEEDS_DECISION: "Manual intervention required - check logs",
        }
        return action_map.get(blocker_code, "Review logs")
    
    def emit_cli(self, notification: Notification):
        """Emit notification to CLI stdout"""
        print(notification.format_cli())
    
    def emit_slack(self, notification: Notification) -> bool:
        """
        Emit notification to Slack (if webhook configured)
        
        Returns True if sent successfully, False otherwise.
        """
        if not self.slack_webhook_url:
            return False
        
        try:
            import urllib.request
            
            payload = {
                "text": notification.format_cli(),
                "mrkdwn": True,
            }
            
            data = json.dumps(payload).encode('utf-8')
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
        """Get recent notifications"""
        return self.notifications[-limit:]
