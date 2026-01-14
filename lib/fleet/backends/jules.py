"""
Jules backend for fleet dispatch.

Handles CLI calls to jules for cloud-based agent work.
"""

import json
import subprocess
from datetime import datetime

from .base import BackendBase, HealthStatus, SessionStatus, SessionInfo


class JulesBackend(BackendBase):
    """Backend for Jules cloud agents."""
    
    def __init__(self, name: str = "jules-cloud", three_gate_required: bool = True):
        super().__init__(name=name, backend_type="jules")
        self.three_gate_required = three_gate_required
    
    def _run_jules(self, args: list[str], timeout: int = 60) -> tuple[int, str, str]:
        """Run jules command and return (returncode, stdout, stderr)."""
        try:
            result = subprocess.run(
                ["jules"] + args,
                capture_output=True,
                text=True,
                timeout=timeout
            )
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return -1, "", "Command timed out"
        except FileNotFoundError:
            return -1, "", "jules CLI not found"
    
    def check_health(self) -> HealthStatus:
        """Check if jules CLI is available."""
        returncode, stdout, stderr = self._run_jules(["--version"], timeout=10)
        if returncode == 0:
            return HealthStatus.HEALTHY
        return HealthStatus.SERVER_UNREACHABLE
    
    def dispatch(
        self, 
        beads_id: str, 
        prompt: str, 
        worktree_path: str,
        system_prompt: str | None = None
    ) -> str:
        """
        Dispatch a task to Jules.
        
        Uses jules create to spawn a cloud session.
        """
        # Build the full prompt
        full_prompt = f"Beads issue: {beads_id}\nWorking directory: {worktree_path}\n\n{prompt}"
        if system_prompt:
            full_prompt = f"{system_prompt}\n\n{full_prompt}"
        
        args = [
            "create",
            "--beads", beads_id,
            "--prompt", full_prompt,
        ]
        
        if self.three_gate_required:
            args.append("--three-gate")
        
        returncode, stdout, stderr = self._run_jules(args, timeout=120)
        
        if returncode != 0:
            raise RuntimeError(f"jules create failed: {stderr}")
        
        # Parse session ID from output
        # Expected: "Created session 12345" or similar
        for line in stdout.split("\n"):
            if "session" in line.lower():
                parts = line.split()
                for part in parts:
                    if part.isdigit():
                        return part
        
        # Fallback: return timestamp-based ID
        return f"jules-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"

    def continue_session(self, session_id: str, prompt: str) -> None:
        """
        Send a follow-up prompt to an existing Jules session.

        Jules CLI does not currently expose a stable "send message to session" primitive
        in this repo’s usage. Keep the method for interface completeness.
        """
        raise NotImplementedError("JulesBackend.continue_session is not supported (no jules CLI subcommand found).")
    
    def get_session_status(self, session_id: str) -> SessionInfo:
        """Get session status from jules remote list."""
        returncode, stdout, stderr = self._run_jules(
            ["remote", "list", "--session", session_id, "--json"],
            timeout=30
        )
        
        if returncode != 0:
            return SessionInfo(
                session_id=session_id,
                status=SessionStatus.UNKNOWN,
                failure_code=stderr
            )
        
        try:
            data = json.loads(stdout)
            status_str = data.get("status", "unknown")
            
            if status_str == "completed":
                status = SessionStatus.IDLE
            elif status_str == "running":
                status = SessionStatus.RUNNING
            elif status_str == "error":
                status = SessionStatus.ERROR
            else:
                status = SessionStatus.UNKNOWN
            
            return SessionInfo(
                session_id=session_id,
                status=status,
                last_activity_ts=data.get("last_activity"),
                pr_url=data.get("pr_url"),
            )
        except json.JSONDecodeError:
            return SessionInfo(
                session_id=session_id,
                status=SessionStatus.UNKNOWN,
                failure_code="Failed to parse jules output"
            )
    
    def get_tool_status(self, session_id: str) -> SessionInfo:
        """Get tool-level status. For Jules, same as session status."""
        return self.get_session_status(session_id)
    
    def abort_session(self, session_id: str) -> bool:
        """Cancel a running jules session."""
        returncode, _, _ = self._run_jules(
            ["remote", "cancel", "--session", session_id],
            timeout=30
        )
        return returncode == 0
    
    def pull_changes(self, session_id: str, apply: bool = False) -> str:
        """Pull changes from a completed jules session."""
        args = ["remote", "pull", "--session", session_id]
        if apply:
            args.append("--apply")
        
        returncode, stdout, stderr = self._run_jules(args, timeout=120)
        
        if returncode != 0:
            raise RuntimeError(f"jules remote pull failed: {stderr}")
        
        return stdout
