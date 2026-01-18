"""
Fleet monitor for session health and stuck detection.

Implements two-level monitoring:
1. Session-level: GET /session/status (bulk)
2. Tool-level: GET /session/:id/message (detailed)
"""

from dataclasses import dataclass
from datetime import datetime
from enum import Enum

from .backends.base import BackendBase, SessionStatus, SessionInfo
from .config import FleetConfig
from .state import FleetStateStore, DispatchRecord


class StuckStatus(Enum):
    """Result of stuck detection check."""
    ACTIVE = "active"
    COMPLETED = "completed"
    ERROR = "error"
    TOOL_HUNG = "tool_hung"
    STALE = "stale"
    TIMEOUT = "timeout"


@dataclass
class MonitorResult:
    """Result of monitoring a single dispatch."""
    session_id: str
    stuck_status: StuckStatus
    session_info: SessionInfo | None = None
    minutes_since_activity: float | None = None
    recommendation: str | None = None


class FleetMonitor:
    """
    Two-level monitoring for fleet dispatches.
    
    Level 1: Session status (fast, bulk)
    Level 2: Tool status (detailed, for stuck detection)
    """
    
    def __init__(
        self, 
        config: FleetConfig | None = None,
        state_store: FleetStateStore | None = None
    ):
        self.config = config or FleetConfig()
        self.state_store = state_store or FleetStateStore()
        self._backends: dict[str, BackendBase] = {}
    
    def register_backend(self, backend: BackendBase) -> None:
        """Register a backend for monitoring."""
        self._backends[backend.name] = backend
    
    def get_backend(self, backend_name: str) -> BackendBase | None:
        """Get a registered backend."""
        return self._backends.get(backend_name)
    
    def check_stuck(
        self, 
        dispatch: DispatchRecord, 
        backend: BackendBase,
        mode: str = "real"
    ) -> MonitorResult:
        """
        Check if a dispatch is stuck using two-level monitoring.
        
        1. Primary: Session status (fast)
        2. Secondary: Tool-level status (detailed)
        """
        stale_threshold_min, timeout_min = self.config.monitoring.get_thresholds(mode)
        
        # Level 1: Session status
        session_info = backend.get_session_status(dispatch.session_id)
        
        if session_info.status == SessionStatus.IDLE:
            return MonitorResult(
                session_id=dispatch.session_id,
                stuck_status=StuckStatus.COMPLETED,
                session_info=session_info,
            )
        
        if session_info.status == SessionStatus.ERROR:
            return MonitorResult(
                session_id=dispatch.session_id,
                stuck_status=StuckStatus.ERROR,
                session_info=session_info,
                recommendation="Check logs and retry"
            )
        
        # Level 2: Tool-level stuck detection
        tool_info = backend.get_tool_status(dispatch.session_id)

        minutes_since_activity = None
        has_any_activity = tool_info.last_tool_name is not None or tool_info.output_snippet is not None

        if tool_info.last_activity_ts:
            try:
                last_activity = datetime.fromisoformat(tool_info.last_activity_ts.replace("Z", "+00:00"))
                now = datetime.utcnow()
                if last_activity.tzinfo:
                    now = now.replace(tzinfo=last_activity.tzinfo)
                minutes_since_activity = (now - last_activity).total_seconds() / 60
            except (ValueError, TypeError):
                pass

        # Calculate total time since dispatch (needed for multiple checks)
        started_ts = datetime.fromisoformat(dispatch.started_ts.replace("Z", "+00:00"))
        total_minutes = (datetime.utcnow() - started_ts.replace(tzinfo=None)).total_seconds() / 60

        # Check for tool hang
        if (tool_info.last_tool_status == "running" and
            minutes_since_activity and
            minutes_since_activity > stale_threshold_min):
            return MonitorResult(
                session_id=dispatch.session_id,
                stuck_status=StuckStatus.TOOL_HUNG,
                session_info=tool_info,
                minutes_since_activity=minutes_since_activity,
                recommendation=f"Tool '{tool_info.last_tool_name}' hung for {minutes_since_activity:.1f}m. Abort via /abort, retry with /shell"
            )

        # NEW: Check for "no activity at all" - session created but agent never started
        # This catches the case where dispatch succeeds but agent never runs any tools
        if not has_any_activity:
            # Use a stricter timeout for first activity from config
            first_activity_timeout_min = self.config.monitoring.get_first_activity_timeout(mode)
            if total_minutes > first_activity_timeout_min:
                return MonitorResult(
                    session_id=dispatch.session_id,
                    stuck_status=StuckStatus.TIMEOUT,
                    session_info=tool_info,
                    minutes_since_activity=total_minutes,
                    recommendation=(f"⚠️ INFRA ISSUE: Session had NO activity for {total_minutes:.1f}m. "
                                   f"Agent never started - possible OpenCode/connectivity issue. "
                                   f"Check VM health and retry.")
                )

        # Check for overall timeout (after first activity check)
        if total_minutes > timeout_min:
            # Make it clearer if there was some activity vs no activity
            if not has_any_activity:
                rec = (f"⚠️ INFRA ISSUE: Session ran for {total_minutes:.1f}m with NO agent activity. "
                       f"Possible OpenCode/connectivity failure. Check VM logs and retry.")
            else:
                rec = f"Dispatch exceeded {timeout_min}m timeout after some activity. Abort and report partial progress"
            return MonitorResult(
                session_id=dispatch.session_id,
                stuck_status=StuckStatus.TIMEOUT,
                session_info=tool_info,
                minutes_since_activity=total_minutes,
                recommendation=rec
            )
        
        if minutes_since_activity and minutes_since_activity > stale_threshold_min:
            return MonitorResult(
                session_id=dispatch.session_id,
                stuck_status=StuckStatus.STALE,
                session_info=tool_info,
                minutes_since_activity=minutes_since_activity,
                recommendation=f"No activity for {minutes_since_activity:.1f}m. Check if agent is waiting for input"
            )
        
        # Active and healthy
        return MonitorResult(
            session_id=dispatch.session_id,
            stuck_status=StuckStatus.ACTIVE,
            session_info=tool_info,
            minutes_since_activity=minutes_since_activity,
        )
    
    def monitor_all_active(self, mode: str = "real") -> list[MonitorResult]:
        """
        Monitor all active dispatches.
        
        Returns list of MonitorResult for each active dispatch.
        """
        results = []
        
        for dispatch in self.state_store.get_active_dispatches():
            if dispatch.status != "running":
                continue
            
            backend = self.get_backend(dispatch.backend_name)
            if not backend:
                results.append(MonitorResult(
                    session_id=dispatch.session_id,
                    stuck_status=StuckStatus.ERROR,
                    recommendation=f"Backend '{dispatch.backend_name}' not registered"
                ))
                continue
            
            result = self.check_stuck(dispatch, backend, mode=dispatch.mode or mode)
            results.append(result)
            
            # Update state store based on result
            if result.stuck_status in (StuckStatus.COMPLETED, StuckStatus.ERROR, StuckStatus.TIMEOUT):
                status = "completed" if result.stuck_status == StuckStatus.COMPLETED else "error"
                failure_code = None
                if result.stuck_status == StuckStatus.TIMEOUT:
                    failure_code = "TIMEOUT"
                elif result.stuck_status == StuckStatus.ERROR:
                    failure_code = "ERROR"
                
                pr_url = result.session_info.pr_url if result.session_info else None
                self.state_store.update_status(
                    dispatch.session_id, 
                    status,
                    pr_url=pr_url,
                    failure_code=failure_code
                )
        
        return results
