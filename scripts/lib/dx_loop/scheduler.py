"""
dx-loop scheduler - Unattended cadence loop with no-duplicate-dispatch

Implements the control cycle with hard separation between:
1. Scheduler wake-up - Cadence timer expires
2. State polling - Check active task progress
3. Dispatch logic - Only dispatch if NOT already running

This prevents the P0 bug: redispatching active work every cadence.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional, Dict, Any, Set, List
from pathlib import Path
import time
import json


@dataclass
class SchedulerState:
    """
    Tracks scheduler state including active dispatches
    
    Critical for preventing duplicate dispatch of already-running work.
    """
    active_beads_ids: Set[str] = field(default_factory=set)
    completed_beads_ids: Set[str] = field(default_factory=set)
    blocked_beads_ids: Set[str] = field(default_factory=set)
    last_poll_time: Optional[str] = None
    poll_count: int = 0
    dispatch_count: int = 0
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "active_beads_ids": list(self.active_beads_ids),
            "completed_beads_ids": list(self.completed_beads_ids),
            "blocked_beads_ids": list(self.blocked_beads_ids),
            "last_poll_time": self.last_poll_time,
            "poll_count": self.poll_count,
            "dispatch_count": self.dispatch_count,
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "SchedulerState":
        state = cls()
        state.active_beads_ids = set(data.get("active_beads_ids", []))
        state.completed_beads_ids = set(data.get("completed_beads_ids", []))
        state.blocked_beads_ids = set(data.get("blocked_beads_ids", []))
        state.last_poll_time = data.get("last_poll_time")
        state.poll_count = data.get("poll_count", 0)
        state.dispatch_count = data.get("dispatch_count", 0)
        return state
    
    def is_active(self, beads_id: str) -> bool:
        """Check if task is currently active (dispatched and running)"""
        return beads_id in self.active_beads_ids
    
    def is_completed(self, beads_id: str) -> bool:
        """Check if task has completed"""
        return beads_id in self.completed_beads_ids
    
    def is_blocked(self, beads_id: str) -> bool:
        """Check if task is blocked"""
        return beads_id in self.blocked_beads_ids
    
    def mark_dispatched(self, beads_id: str):
        """Mark task as dispatched"""
        self.active_beads_ids.add(beads_id)
        self.blocked_beads_ids.discard(beads_id)
        self.dispatch_count += 1
    
    def mark_completed(self, beads_id: str):
        """Mark task as completed"""
        self.active_beads_ids.discard(beads_id)
        self.completed_beads_ids.add(beads_id)
        self.blocked_beads_ids.discard(beads_id)
    
    def mark_blocked(self, beads_id: str):
        """Mark task as blocked"""
        self.active_beads_ids.discard(beads_id)
        self.blocked_beads_ids.add(beads_id)
    
    def mark_unblocked(self, beads_id: str):
        """Mark task as no longer blocked"""
        self.blocked_beads_ids.discard(beads_id)


class DxLoopScheduler:
    """
    Scheduler with no-duplicate-dispatch policy
    
    The scheduler maintains a strict set of active dispatches and refuses
    to re-dispatch work that is already running. This fixes the P0 bug.
    """
    
    def __init__(self, cadence_seconds: int = 600):
        self.cadence_seconds = cadence_seconds
        self.state = SchedulerState()
    
    def run_cycle(
        self,
        get_ready_tasks_fn,
        dispatch_task_fn,
        check_progress_fn,
        max_iterations: int = 100,
    ) -> bool:
        """
        Run scheduler cycle with no-duplicate-dispatch
        
        Args:
            get_ready_tasks_fn: () -> List[beads_id] - Get ready tasks
            dispatch_task_fn: (beads_id) -> bool - Dispatch single task
            check_progress_fn: () -> None - Check active task progress
            max_iterations: Maximum cadence iterations
        
        Returns:
            True if wave complete, False if stopped/blocked
        """
        iteration = 0
        
        while iteration < max_iterations:
            iteration += 1
            
            # PHASE 1: Wake-up
            now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            self.state.last_poll_time = now
            self.state.poll_count += 1
            
            # PHASE 2: Poll active task progress
            check_progress_fn()
            
            # PHASE 3: Dispatch new work (ONLY if not already active)
            ready_tasks = get_ready_tasks_fn()
            
            if not ready_tasks:
                if not self.state.active_beads_ids:
                    # No ready tasks and no active tasks - wave complete
                    return True
                # Active work still running, just wait
            else:
                # Filter out already-active tasks (P0 fix)
                new_tasks = [
                    tid for tid in ready_tasks
                    if not self.state.is_active(tid)
                    and not self.state.is_completed(tid)
                ]
                
                if new_tasks:
                    for beads_id in new_tasks:
                        if dispatch_task_fn(beads_id):
                            self.state.mark_dispatched(beads_id)
            
            # Sleep until next cadence
            time.sleep(self.cadence_seconds)
        
        return False
    
    def get_state(self) -> SchedulerState:
        return self.state
    
    def load_state(self, state: SchedulerState):
        self.state = state
