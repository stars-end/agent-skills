"""
Base class for fleet backends.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum


class HealthStatus(Enum):
    """Health status of a backend."""
    HEALTHY = "healthy"
    SERVER_UNHEALTHY = "server_unhealthy"
    SERVER_UNREACHABLE = "server_unreachable"
    SERVER_PORT_CONFLICT = "server_port_conflict"


class SessionStatus(Enum):
    """Status of a dispatch session."""
    RUNNING = "running"
    IDLE = "idle"  # Completed successfully
    ERROR = "error"
    TOOL_HUNG = "tool_hung"
    TIMEOUT = "timeout"
    UNKNOWN = "unknown"


@dataclass
class SessionInfo:
    """Information about a session."""
    session_id: str
    status: SessionStatus
    last_activity_ts: str | None = None
    last_tool_name: str | None = None
    last_tool_status: str | None = None
    output_snippet: str | None = None
    pr_url: str | None = None
    failure_code: str | None = None


class BackendBase(ABC):
    """Abstract base class for fleet backends (OpenCode, Jules, etc)."""
    
    def __init__(self, name: str, backend_type: str):
        self.name = name
        self.backend_type = backend_type
    
    @abstractmethod
    def check_health(self) -> HealthStatus:
        """Check if the backend is healthy and reachable."""
        pass
    
    @abstractmethod
    def dispatch(
        self, 
        beads_id: str, 
        prompt: str, 
        worktree_path: str,
        system_prompt: str | None = None
    ) -> str:
        """
        Dispatch a task to the backend.
        
        Returns the session ID.
        """
        pass
    
    @abstractmethod
    def continue_session(
        self,
        session_id: str,
        prompt: str
    ) -> None:
        """
        Send a follow-up prompt to an existing session.
        """
        pass
    
    @abstractmethod
    def get_session_status(self, session_id: str) -> SessionInfo:
        """Get the status of a session."""
        pass
    
    @abstractmethod
    def get_tool_status(self, session_id: str) -> SessionInfo:
        """Get detailed tool-level status for stuck detection."""
        pass
    
    @abstractmethod
    def abort_session(self, session_id: str) -> bool:
        """Abort a running session. Returns True if successful."""
        pass
    
    def shell_command(self, session_id: str, command: str) -> str:
        """Run a shell command in the session. Default: not supported."""
        raise NotImplementedError(f"{self.backend_type} does not support shell commands")
    
    def finalize_pr(
        self, 
        session_id: str, 
        beads_id: str, 
        smoke_mode: bool = False
    ) -> str | None:
        """Create a PR from session changes. Default: not supported."""
        raise NotImplementedError(f"{self.backend_type} does not support PR finalization")
