"""
Sandbox backend (placeholder).

This exists to keep the FleetDispatcher interface stable for a future world
where dx-dispatch can target ephemeral sandbox environments (containers/VMs).

It is intentionally non-functional unless a real sandbox backend is implemented.
"""

from .base import BackendBase, HealthStatus, SessionInfo, SessionStatus


class SandboxBackend(BackendBase):
    """Non-functional placeholder backend for future sandbox environments."""

    def __init__(self, name: str):
        super().__init__(name=name, backend_type="sandbox")

    def check_health(self) -> HealthStatus:
        # Placeholder backends should never be auto-selected.
        return HealthStatus.SERVER_UNREACHABLE

    def dispatch(self, beads_id: str, prompt: str, worktree_path: str, system_prompt: str | None = None) -> str:
        raise RuntimeError("sandbox backend is not implemented")

    def continue_session(self, session_id: str, prompt: str) -> None:
        raise RuntimeError("sandbox backend is not implemented")

    def get_session_status(self, session_id: str) -> SessionInfo:
        return SessionInfo(session_id=session_id, status=SessionStatus.UNKNOWN)

    def get_tool_status(self, session_id: str) -> SessionInfo:
        return SessionInfo(session_id=session_id, status=SessionStatus.UNKNOWN)

    def abort_session(self, session_id: str) -> bool:
        return False

