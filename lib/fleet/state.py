"""
Fleet state management.

Manages ~/.agent-skills/fleet-state.json for orchestrator handoff.
"""

import json
import os
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Any


@dataclass
class DispatchRecord:
    """Record of a single dispatch."""
    beads_id: str
    session_id: str
    backend_type: str  # "opencode" or "jules"
    backend_name: str  # e.g., "epyc6", "jules-cloud"
    vm_url: str | None  # For OpenCode
    repo: str
    mode: str  # "smoke" or "real"
    started_ts: str
    status: str  # "running", "completed", "error", "timeout"
    slack_message_ts: str | None = None
    slack_thread_ts: str | None = None
    pr_url: str | None = None
    failure_code: str | None = None
    completed_ts: str | None = None
    
    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {k: v for k, v in asdict(self).items() if v is not None}
    
    @classmethod
    def from_dict(cls, data: dict) -> "DispatchRecord":
        """Create from dictionary."""
        return cls(
            beads_id=data.get("beads_id", ""),
            session_id=data.get("session_id", ""),
            backend_type=data.get("backend_type", "opencode"),
            backend_name=data.get("backend_name", ""),
            vm_url=data.get("vm_url"),
            repo=data.get("repo", ""),
            mode=data.get("mode", "real"),
            started_ts=data.get("started_ts", ""),
            status=data.get("status", "running"),
            slack_message_ts=data.get("slack_message_ts"),
            slack_thread_ts=data.get("slack_thread_ts"),
            pr_url=data.get("pr_url"),
            failure_code=data.get("failure_code"),
            completed_ts=data.get("completed_ts"),
        )


class FleetStateStore:
    """Manage fleet dispatch state for orchestrator handoff."""
    
    def __init__(self, state_path: Path | None = None):
        self.state_path = state_path or (Path.home() / ".agent-skills" / "fleet-state.json")
        self._ensure_directory()
    
    def _ensure_directory(self) -> None:
        """Ensure the parent directory exists."""
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
    
    def load(self) -> dict:
        """Load state from file."""
        if not self.state_path.exists():
            return {"active_dispatches": []}
        
        try:
            with open(self.state_path) as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Failed to load fleet-state.json: {e}")
            return {"active_dispatches": []}
    
    def save(self, state: dict) -> None:
        """Save state to file."""
        try:
            with open(self.state_path, "w") as f:
                json.dump(state, f, indent=2)
        except IOError as e:
            print(f"Warning: Failed to save fleet-state.json: {e}")
    
    def get_active_dispatches(self) -> list[DispatchRecord]:
        """Get all active (running) dispatches."""
        state = self.load()
        return [
            DispatchRecord.from_dict(d) 
            for d in state.get("active_dispatches", [])
        ]
    
    def save_dispatch(self, record: DispatchRecord) -> None:
        """Add a new dispatch record."""
        state = self.load()
        dispatches = state.get("active_dispatches", [])
        dispatches.append(record.to_dict())
        state["active_dispatches"] = dispatches
        self.save(state)
    
    def update_status(
        self, 
        session_id: str, 
        status: str, 
        pr_url: str | None = None,
        failure_code: str | None = None
    ) -> None:
        """Update the status of an existing dispatch."""
        state = self.load()
        dispatches = state.get("active_dispatches", [])
        
        for dispatch in dispatches:
            if dispatch.get("session_id") == session_id:
                dispatch["status"] = status
                if pr_url:
                    dispatch["pr_url"] = pr_url
                if failure_code:
                    dispatch["failure_code"] = failure_code
                if status in ("completed", "error", "timeout"):
                    dispatch["completed_ts"] = datetime.utcnow().isoformat()
                break
        
        state["active_dispatches"] = dispatches
        self.save(state)
    
    def find_active_dispatch(
        self, 
        beads_id: str, 
        backend_type: str, 
        backend_name: str, 
        repo: str, 
        mode: str
    ) -> DispatchRecord | None:
        """Find an active dispatch by idempotency key."""
        for record in self.get_active_dispatches():
            if (record.beads_id == beads_id and 
                record.backend_type == backend_type and
                record.backend_name == backend_name and
                record.repo == repo and
                record.mode == mode and
                record.status == "running"):
                return record
        return None
    
    def find_by_session_id(self, session_id: str) -> DispatchRecord | None:
        """Find a dispatch by session ID."""
        for record in self.get_active_dispatches():
            if record.session_id == session_id:
                return record
        return None
    
    def remove_completed(self, max_age_hours: int = 24) -> int:
        """Remove completed dispatches older than max_age_hours. Returns count removed."""
        state = self.load()
        dispatches = state.get("active_dispatches", [])
        
        cutoff = datetime.utcnow().timestamp() - (max_age_hours * 3600)
        
        remaining = []
        removed = 0
        for dispatch in dispatches:
            if dispatch.get("status") in ("completed", "error", "timeout"):
                completed_ts = dispatch.get("completed_ts")
                if completed_ts:
                    try:
                        completed = datetime.fromisoformat(completed_ts).timestamp()
                        if completed < cutoff:
                            removed += 1
                            continue
                    except ValueError:
                        pass
            remaining.append(dispatch)
        
        state["active_dispatches"] = remaining
        self.save(state)
        return removed
