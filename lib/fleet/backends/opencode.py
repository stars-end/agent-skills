"""
OpenCode backend for fleet dispatch.

Handles HTTP calls to OpenCode servers running on VMs.
"""

import json
import subprocess
from dataclasses import dataclass
from datetime import datetime
from typing import Any
from urllib.parse import urljoin

try:
    import requests
except ImportError:
    requests = None  # Will use subprocess fallback

from .base import BackendBase, HealthStatus, SessionStatus, SessionInfo


class OpenCodeBackend(BackendBase):
    """Backend for OpenCode servers on VMs."""
    
    def __init__(
        self, 
        name: str, 
        url: str, 
        ssh_target: str | None = None,
        timeout: int = 30
    ):
        super().__init__(name=name, backend_type="opencode")
        self.url = url.rstrip("/")
        self.ssh_target = ssh_target
        self.timeout = timeout
    
    def _http_get(self, path: str) -> dict:
        """Make HTTP GET request."""
        url = urljoin(self.url + "/", path.lstrip("/"))
        
        if requests:
            response = requests.get(url, timeout=self.timeout)
            response.raise_for_status()
            return response.json()
        else:
            # Fallback to curl
            result = subprocess.run(
                ["curl", "-s", "-f", url],
                capture_output=True,
                text=True,
                timeout=self.timeout
            )
            if result.returncode != 0:
                raise RuntimeError(f"HTTP GET failed: {result.stderr}")
            return json.loads(result.stdout)
    
    def _http_post(self, path: str, data: dict) -> dict:
        """Make HTTP POST request."""
        url = urljoin(self.url + "/", path.lstrip("/"))
        
        if requests:
            response = requests.post(
                url, 
                json=data, 
                timeout=self.timeout,
                headers={"Content-Type": "application/json"}
            )
            response.raise_for_status()
            if response.status_code == 204:
                return {}
            return response.json()
        else:
            # Fallback to curl
            result = subprocess.run(
                [
                    "curl", "-s", "-f", "-X", "POST",
                    "-H", "Content-Type: application/json",
                    "-d", json.dumps(data),
                    url
                ],
                capture_output=True,
                text=True,
                timeout=self.timeout
            )
            if result.returncode != 0:
                raise RuntimeError(f"HTTP POST failed: {result.stderr}")
            if not result.stdout.strip():
                return {}
            return json.loads(result.stdout)
    
    def check_health(self) -> HealthStatus:
        """Check if the OpenCode server is healthy."""
        try:
            response = self._http_get("/global/health")
            # Observed in practice: {"healthy": true, "version": "..."}
            # (Docs may evolve; tolerate both shapes.)
            if response.get("healthy") is True or response.get("status") == "ok":
                return HealthStatus.HEALTHY
            return HealthStatus.SERVER_UNHEALTHY
        except Exception as e:
            error_msg = str(e).lower()
            if "connection" in error_msg or "unreachable" in error_msg:
                return HealthStatus.SERVER_UNREACHABLE
            if "port" in error_msg or "restart" in error_msg:
                return HealthStatus.SERVER_PORT_CONFLICT
            return HealthStatus.SERVER_UNHEALTHY
    
    def dispatch(
        self, 
        beads_id: str, 
        prompt: str, 
        worktree_path: str,
        system_prompt: str | None = None
    ) -> str:
        """
        Dispatch a task to OpenCode.
        
        Creates a new session and sends the prompt asynchronously.
        """
        # 1. Create session
        # Server docs: POST /session supports { parentID?, title? }. Do not rely on cwd fields.
        create_data: dict[str, Any] = {"title": beads_id}
        create_response = self._http_post("/session", create_data)
        session_id = create_response.get("id")
        
        if not session_id:
            raise RuntimeError(f"Failed to create session: {create_response}")
        
        # 2. Send worktree/system context (non-blocking; no agent reply expected).
        context = (
            f"IMPORTANT: You are working in an isolated worktree at:\n{worktree_path}\n\n"
            f"You MUST run `cd {worktree_path} && pwd` as your first command.\n"
            f"All edits/commits must happen in that directory.\n\n"
            f"Beads issue: {beads_id}\n"
        )
        if system_prompt:
            context += f"\nSystem context:\n{system_prompt}\n"
        self._http_post(
            f"/session/{session_id}/message",
            {"noReply": True, "parts": [{"type": "text", "text": context}]},
        )
        
        # 3. Send task asynchronously
        self.continue_session(session_id, prompt)
        
        return session_id

    def continue_session(self, session_id: str, prompt: str) -> None:
        """Send a follow-up prompt to an existing session (async)."""
        # Prefer prompt_async to avoid blocking.
        try:
            self._http_post(f"/session/{session_id}/prompt_async", {"parts": [{"type": "text", "text": prompt}]})
        except Exception:
            # Best-effort: fall back to blocking message if prompt_async isn't available.
            self._http_post(f"/session/{session_id}/message", {"parts": [{"type": "text", "text": prompt}]})
    
    def continue_session(self, session_id: str, prompt: str) -> None:
        """Send a follow-up prompt to an existing session."""
        try:
            self._http_post(f"/session/{session_id}/prompt_async", {
                "parts": [{"type": "text", "text": prompt}]
            })
        except Exception:
            # prompt_async returns 204, which may error on some HTTP libs if parsing JSON response
            pass
    
    def get_session_status(self, session_id: str) -> SessionInfo:
        """Get session status from bulk endpoint."""
        try:
            # Observed in practice: /session/status returns ONLY busy sessions:
            # { "<id>": {"type": "busy"} }
            all_status = self._http_get("/session/status")
            session_data = all_status.get(session_id)
            if session_data:
                return SessionInfo(session_id=session_id, status=SessionStatus.RUNNING)

            # If not present, treat as idle if the session exists.
            details = self._http_get(f"/session/{session_id}")
            updated_ms = (details.get("time") or {}).get("updated")
            last_activity_ts = None
            if isinstance(updated_ms, int):
                last_activity_ts = datetime.utcfromtimestamp(updated_ms / 1000).isoformat()
            return SessionInfo(
                session_id=session_id,
                status=SessionStatus.IDLE,
                last_activity_ts=last_activity_ts,
            )
        except Exception as e:
            return SessionInfo(
                session_id=session_id,
                status=SessionStatus.UNKNOWN,
                failure_code=str(e)
            )
    
    def get_tool_status(self, session_id: str) -> SessionInfo:
        """
        Get tool-level status for stuck detection.
        
        Scans message history for parts with type='tool' and reads state.
        """
        try:
            messages = self._http_get(f"/session/{session_id}/message")
            
            # Scan for the last tool
            last_tool_name = None
            last_tool_status = None
            last_tool_started = None
            output_snippet = None
            
            for msg in reversed(messages if isinstance(messages, list) else []):
                parts = msg.get("parts", [])
                for part in parts:
                    if part.get("type") == "tool":
                        state = part.get("state", {})
                        last_tool_name = part.get("tool") or part.get("name")
                        last_tool_status = state.get("status")
                        time_info = state.get("time", {})
                        last_tool_started = time_info.get("start")
                        output_snippet = str(state.get("output", ""))[:200]
                        break
                if last_tool_name:
                    break
            
            # Determine session status from tool status
            status = SessionStatus.RUNNING
            if last_tool_status == "running" and last_tool_started:
                # Check if tool is stale (this is just for info; threshold check is in monitor)
                pass
            elif last_tool_status == "completed":
                status = SessionStatus.RUNNING  # Tool completed but session may continue
            elif last_tool_status == "error":
                status = SessionStatus.ERROR
            
            last_activity_ts = None
            if isinstance(last_tool_started, int):
                last_activity_ts = datetime.utcfromtimestamp(last_tool_started / 1000).isoformat()
            elif isinstance(last_tool_started, str):
                last_activity_ts = last_tool_started

            return SessionInfo(
                session_id=session_id,
                status=status,
                last_activity_ts=last_activity_ts,
                last_tool_name=last_tool_name,
                last_tool_status=last_tool_status,
                output_snippet=output_snippet,
            )
        except Exception as e:
            return SessionInfo(
                session_id=session_id,
                status=SessionStatus.UNKNOWN,
                failure_code=str(e)
            )
    
    def abort_session(self, session_id: str) -> bool:
        """Abort a running session."""
        try:
            self._http_post(f"/session/{session_id}/abort", {})
            return True
        except Exception:
            return False
    
    def shell_command(self, session_id: str, command: str, agent: str = "build") -> str:
        """Run a shell command in the session."""
        response = self._http_post(f"/session/{session_id}/shell", {
            "agent": agent,
            "command": command
        })
        # Server returns {info, parts:[{type:'tool', state:{status, output, error?}}]}
        parts = response.get("parts", []) if isinstance(response, dict) else []
        for part in parts:
            if not isinstance(part, dict):
                continue
            if part.get("type") != "tool":
                continue
            state = part.get("state") or {}
            status = state.get("status")
            if status == "error":
                err = (state.get("error") or {}).get("message") or state.get("output") or "shell error"
                raise RuntimeError(str(err))
            output = state.get("output")
            if isinstance(output, str):
                return output
        return ""
    
    def finalize_pr(
        self, 
        session_id: str, 
        beads_id: str, 
        smoke_mode: bool = False
    ) -> str | None:
        """Create a PR from session changes."""
        # Stage and commit
        commit_cmd = (
            f"git add -A && git commit --allow-empty -m 'chore({beads_id}): smoke dispatch'"
            if smoke_mode
            else f"git add -A && git commit -m 'fix({beads_id}): automated fix'"
        )
        self.shell_command(
            session_id, 
            commit_cmd
        )
        
        # Push (with or without verification)
        push_cmd = "git push --no-verify -u origin HEAD" if smoke_mode else "git push -u origin HEAD"
        try:
            self.shell_command(session_id, push_cmd)
        except Exception as e:
            if "ci-lite" in str(e).lower() or "pre-push" in str(e).lower():
                return None  # Will be classified as PUSH_BLOCKED_CI_LITE
            raise
        
        # Create PR
        pr_output = self.shell_command(session_id, "gh pr create --fill")
        
        # Parse PR URL from output
        for line in pr_output.split("\n"):
            if "github.com" in line and "/pull/" in line:
                return line.strip()
        
        return None
    
    def get_diff(self, session_id: str) -> str:
        """Get cumulative changes from the session."""
        try:
            diffs = self._http_get(f"/session/{session_id}/diff")
            # Docs: returns FileDiff[]. Keep it simple and JSON-dump as fallback.
            if isinstance(diffs, str):
                return diffs
            return json.dumps(diffs)[:2000]
        except Exception:
            return ""
