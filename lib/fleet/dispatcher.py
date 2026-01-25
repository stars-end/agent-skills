"""
Fleet dispatcher - main orchestrator for fleet dispatch.

Usage:
    from lib.fleet import FleetDispatcher, DispatchResult
    
    dispatcher = FleetDispatcher()
    result = dispatcher.dispatch(
        beads_id="bd-xxx",
        prompt="Fix the bug",
        repo="prime-radiant-ai",
        mode="real"
    )
"""

import subprocess
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from .backends.base import BackendBase, HealthStatus, SessionStatus
from .backends.opencode import OpenCodeBackend
from .backends.jules import JulesBackend
from .config import FleetConfig, BackendConfig
from .state import FleetStateStore, DispatchRecord
from .monitor import FleetMonitor, StuckStatus, MonitorResult
from .event_emitter import EventEmitter


@dataclass
class DispatchResult:
    """Result of a dispatch operation."""
    success: bool
    session_id: str = ""
    backend_name: str = ""
    backend_type: str = ""
    vm_url: str | None = None
    worktree_path: str = ""
    was_duplicate: bool = False
    error: str | None = None
    failure_code: str | None = None


class FleetDispatcher:
    """
    Main orchestrator for fleet dispatch.
    
    Handles:
    - Backend selection (OpenCode vs Jules)
    - Worktree setup
    - Dispatch with idempotency
    - Monitoring integration
    """
    
    def __init__(
        self, 
        config: FleetConfig | None = None,
        state_store: FleetStateStore | None = None
    ):
        self.config = config or FleetConfig()
        self.state_store = state_store or FleetStateStore()
        self.monitor = FleetMonitor(config=self.config, state_store=self.state_store)
        self.event_emitter = EventEmitter(sender="fleet-dispatcher")
        self._backends: dict[str, BackendBase] = {}
        self._init_backends()
    
    def _init_backends(self) -> None:
        """Initialize backends from config."""
        for backend_config in self.config.backends:
            if backend_config.type == "opencode" and backend_config.url:
                backend = OpenCodeBackend(
                    name=backend_config.name,
                    url=backend_config.url,
                    ssh_target=backend_config.ssh,
                )
            elif backend_config.type == "jules":
                backend = JulesBackend(
                    name=backend_config.name,
                    three_gate_required=backend_config.three_gate_required,
                )
            else:
                continue
            
            self._backends[backend_config.name] = backend
            self.monitor.register_backend(backend)
    
    def get_backend(self, name: str) -> BackendBase | None:
        """Get a specific backend by name."""
        return self._backends.get(name)
    
    def select_backend(
        self, 
        preferred: str | None = None,
        require_opencode: bool = False
    ) -> tuple[BackendBase, BackendConfig] | None:
        """
        Select the best available backend.
        
        Priority:
        1. Preferred backend (if specified and healthy)
        2. Highest priority healthy OpenCode backend
        3. Jules (if not require_opencode)
        """
        # Check preferred backend first
        if preferred:
            for bc in self.config.backends:
                if bc.name == preferred:
                    backend = self._backends.get(bc.name)
                    if backend and backend.check_health() == HealthStatus.HEALTHY:
                        return (backend, bc)
                    break
        
        # Try OpenCode backends by priority
        for bc in self.config.get_opencode_backends():
            backend = self._backends.get(bc.name)
            if backend and backend.check_health() == HealthStatus.HEALTHY:
                return (backend, bc)
        
        # Fallback to Jules
        if not require_opencode:
            bc = self.config.get_jules_backend()
            if bc:
                backend = self._backends.get(bc.name)
                if backend and backend.check_health() == HealthStatus.HEALTHY:
                    return (backend, bc)
        
        return None
    
    def auto_select_task(self, repo: str = "affordabot") -> str | None:
        """Use BV robot-plan to select next task for auto-dispatch.
        
        Returns the Beads ID of the highest-impact unblocked task,
        or None if BV is not installed or fails.
        
        Usage:
            dispatcher = FleetDispatcher()
            next_task = dispatcher.auto_select_task("affordabot")
            if next_task:
                dispatcher.dispatch(beads_id=next_task, ...)
        """
        import json
        
        try:
            result = subprocess.run(
                ["bv", "--robot-plan"],
                capture_output=True, 
                text=True, 
                timeout=10,
                cwd=str(Path.home() / repo)
            )
            if result.returncode == 0:
                plan = json.loads(result.stdout)
                return plan.get("summary", {}).get("highest_impact")
        except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
            # BV not installed or failed - gracefully degrade
            pass
        return None
    
    def setup_worktree(
        self, 
        backend: BackendBase, 
        backend_config: BackendConfig,
        beads_id: str, 
        repo: str
    ) -> str:
        """
        Set up a worktree for agent work.
        
        For OpenCode: SSH to VM and create worktree
        For Jules: Local worktree (or skip if cloud-only)
        """
        if backend_config.type == "jules":
            # Jules handles its own workspace
            return f"/tmp/jules/{beads_id}"
        
        # Determine script command
        script_cmd = f"worktree-setup.sh {beads_id} {repo}"
        # Try to find script in path or repo
        if not backend_config.ssh:
            # Local execution
            import shutil
            script_path = shutil.which("worktree-setup.sh")
            if not script_path:
                # Fallback to repo path if running from repo
                repo_script = Path(__file__).parent.parent.parent / "scripts" / "worktree-setup.sh"
                if repo_script.exists():
                    script_path = str(repo_script)
                else:
                    script_path = str(Path.home() / "bin" / "worktree-setup.sh")
            
            cmd = [script_path, beads_id, repo]
            try:
                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    timeout=60,
                )
                if result.returncode == 0:
                    path = result.stdout.strip()
                    # Trust mise locally
                    subprocess.run(f"mise trust --yes {path}/.mise.toml", shell=True, check=False)
                    return path
                else:
                    raise RuntimeError(f"Worktree setup failed: {result.stderr}")
            except Exception as e:
                raise RuntimeError(f"Local worktree setup failed: {e}")

        else:
            # Remote execution
            if not backend_config.ssh:
                 raise RuntimeError(f"OpenCode backend {backend_config.name} has no SSH target")

            # Best-effort: ensure the control plane (agent-skills) and ~/bin tools are fresh on the target VM.
            # This is intentionally non-blocking: dispatch should still proceed if the VM is temporarily offline.
            try:
                pre_cmd = (
                    'export PATH="$HOME/.local/bin:$HOME/bin:$PATH"; '
                    'command -v ru >/dev/null 2>&1 && ru sync agent-skills --non-interactive --quiet || true; '
                    '~/agent-skills/scripts/dx-ensure-bins.sh >/dev/null 2>&1 || true'
                )
                subprocess.run(
                    ["ssh", backend_config.ssh, pre_cmd],
                    capture_output=True,
                    text=True,
                    timeout=60,
                )
            except Exception:
                pass

            # Try canonical script first (preferred, repo-aware).
            try:
                result = subprocess.run(
                    ["ssh", backend_config.ssh, f"~/bin/{script_cmd}"],
                    capture_output=True,
                    text=True,
                    timeout=60,
                )
                if result.returncode == 0:
                    script_path = (result.stdout or "").strip()
                    if script_path.startswith("/"):
                        # Best-effort: trust mise config inside the worktree.
                        subprocess.run(
                            ["ssh", backend_config.ssh, f"mise trust --yes {script_path}/.mise.toml 2>/dev/null || true"],
                            capture_output=True,
                            text=True,
                            timeout=30,
                        )
                        return script_path
            except Exception:
                pass

        # Fallback: inline worktree setup
        # NOTE: This assumes a bare repo clone exists at ~/{repo}; in your stack the
        # canonical script is the source of truth (and is strongly preferred).
        repo_path = f"~/{repo}"
        worktree_path = f"/tmp/agents/{beads_id}/{repo}"
        commands = [
            f"cd {repo_path} && git worktree add {worktree_path} -b {beads_id}",
            f"mise trust --yes {worktree_path}/.mise.toml 2>/dev/null || true",
        ]
        
        for cmd in commands:
            subprocess.run(
                ["ssh", backend_config.ssh, cmd],
                capture_output=True,
                text=True,
                timeout=60
            )
        
        return worktree_path
    
    def dispatch(
        self,
        beads_id: str,
        prompt: str,
        repo: str,
        mode: str = "real",
        preferred_backend: str | None = None,
        system_prompt: str | None = None,
        slack_message_ts: str | None = None,
        slack_thread_ts: str | None = None,
    ) -> DispatchResult:
        """
        Dispatch a task to the fleet.
        
        Args:
            beads_id: Beads issue ID (e.g., "bd-xxx")
            prompt: Task prompt for the agent
            repo: Repository name (e.g., "prime-radiant-ai")
            mode: "smoke" or "real" (affects thresholds)
            preferred_backend: Specific backend to use (e.g., "epyc6")
            system_prompt: Optional system context
            slack_message_ts: Slack message ts for edits
            slack_thread_ts: Slack thread ts
        
        Returns:
            DispatchResult with session info
        """
        # 1. Select backend
        selection = self.select_backend(preferred=preferred_backend)
        if not selection:
            return DispatchResult(
                success=False,
                error="No healthy backends available",
                failure_code="SERVER_UNREACHABLE"
            )
        
        backend, backend_config = selection
        
        # 2. Check idempotency
        existing = self.state_store.find_active_dispatch(
            beads_id=beads_id,
            backend_type=backend_config.type,
            backend_name=backend_config.name,
            repo=repo,
            mode=mode
        )
        
        if existing:
            return DispatchResult(
                success=True,
                session_id=existing.session_id,
                backend_name=existing.backend_name,
                backend_type=existing.backend_type,
                vm_url=existing.vm_url,
                was_duplicate=True
            )
        
        # 3. Health check
        health = backend.check_health()
        if health != HealthStatus.HEALTHY:
            return DispatchResult(
                success=False,
                backend_name=backend_config.name,
                error=f"Backend unhealthy: {health.value}",
                failure_code=health.value.upper()
            )
        
        # 4. Setup worktree (OpenCode only)
        try:
            worktree_path = self.setup_worktree(backend, backend_config, beads_id, repo)
        except Exception as e:
            return DispatchResult(
                success=False,
                backend_name=backend_config.name,
                error=f"Worktree setup failed: {e}",
                failure_code="WORKTREE_FAILED"
            )
        
        # 5. Dispatch
        try:
            session_id = backend.dispatch(
                beads_id=beads_id,
                prompt=prompt,
                worktree_path=worktree_path,
                system_prompt=system_prompt
            )
        except Exception as e:
            return DispatchResult(
                success=False,
                backend_name=backend_config.name,
                error=f"Dispatch failed: {e}",
                failure_code="DISPATCH_FAILED"
            )
        
        # 6. Save to state store
        record = DispatchRecord(
            beads_id=beads_id,
            session_id=session_id,
            backend_type=backend_config.type,
            backend_name=backend_config.name,
            vm_url=backend_config.url,
            repo=repo,
            mode=mode,
            started_ts=datetime.utcnow().isoformat(),
            status="running",
            slack_message_ts=slack_message_ts,
            slack_thread_ts=slack_thread_ts,
        )
        self.state_store.save_dispatch(record)
        
        # 7. Emit DISPATCH_REQUEST event to Agent Event Bus
        try:
            self.event_emitter.emit(
                event_type="DISPATCH_REQUEST",
                repo=repo,
                beads_id=beads_id,
                payload={
                    "backend": f"{backend_config.type}:{backend_config.name}",
                    "session_id": session_id,
                    "prompt": prompt[:200],  # Truncate for event
                    "mode": mode,
                },
                thread_ts=slack_thread_ts,
            )
        except Exception as e:
            # Don't fail dispatch if event emission fails
            print(f"Warning: Failed to emit DISPATCH_REQUEST event: {e}")
        
        return DispatchResult(
            success=True,
            session_id=session_id,
            backend_name=backend_config.name,
            backend_type=backend_config.type,
            vm_url=backend_config.url,
            worktree_path=worktree_path,
        )
    
    def continue_session(self, session_id: str, prompt: str) -> bool:
        """
        Send a follow-up prompt to an existing session.
        Returns True if successful, False if session/backend not found.
        """
        record = self.state_store.find_by_session_id(session_id)
        if not record:
            return False
        
        backend = self._backends.get(record.backend_name)
        if not backend:
            return False
        
        try:
            backend.continue_session(session_id, prompt)
            return True
        except Exception as e:
            print(f"Error continuing session: {e}")
            return False
    
    def get_status(self, session_id: str) -> dict:
        """
        Get status of a dispatch.
        
        Returns dict with:
            status: "running" | "completed" | "error" | "timeout"
            failure_code: optional error code
            pr_url: optional PR URL if completed
        """
        record = self.state_store.find_by_session_id(session_id)
        if not record:
            return {"status": "unknown", "error": "Session not found"}
        
        backend = self._backends.get(record.backend_name)
        if not backend:
            return {"status": "unknown", "error": "Backend not found"}
        
        # Check current status
        result = self.monitor.check_stuck(record, backend, mode=record.mode)
        
        status_map = {
            StuckStatus.COMPLETED: "completed",
            StuckStatus.ERROR: "error",
            StuckStatus.TIMEOUT: "timeout",
            StuckStatus.TOOL_HUNG: "running",  # Still running, but stuck
            StuckStatus.STALE: "running",
            StuckStatus.ACTIVE: "running",
        }
        
        response = {
            "status": status_map.get(result.stuck_status, "unknown"),
            "session_id": session_id,
            "backend": record.backend_name,
        }
        
        if result.stuck_status == StuckStatus.COMPLETED and result.session_info:
            response["pr_url"] = result.session_info.pr_url
        
        if result.stuck_status in (StuckStatus.ERROR, StuckStatus.TIMEOUT, StuckStatus.TOOL_HUNG):
            response["failure_code"] = result.stuck_status.value.upper()
            response["recommendation"] = result.recommendation
        
        return response
    
    def wait_for_completion(
        self, 
        session_id: str, 
        poll_interval_sec: int = 60,
        max_polls: int = 30
    ) -> dict:
        """
        Poll until dispatch completes.
        
        Returns status dict when done or max_polls reached.
        """
        import time
        
        for _ in range(max_polls):
            status = self.get_status(session_id)
            if status.get("status") in ("completed", "error", "timeout"):
                return status
            time.sleep(poll_interval_sec)
        
        return {"status": "timeout", "failure_code": "POLL_TIMEOUT"}
    
    def finalize_pr(
        self, 
        session_id: str, 
        beads_id: str, 
        smoke_mode: bool = False
    ) -> str | None:
        """
        Finalize a dispatch by creating a PR.
        
        Returns PR URL or None if failed.
        """
        record = self.state_store.find_by_session_id(session_id)
        if not record:
            return None
        
        backend = self._backends.get(record.backend_name)
        if not backend:
            return None
        
        if not hasattr(backend, "finalize_pr"):
            return None
        
        try:
            pr_url = backend.finalize_pr(session_id, beads_id, smoke_mode=smoke_mode)
            if pr_url:
                self.state_store.update_status(session_id, "completed", pr_url=pr_url)
            return pr_url
        except Exception as e:
            error_msg = str(e).lower()
            if "ci-lite" in error_msg or "pre-push" in error_msg:
                self.state_store.update_status(
                    session_id, 
                    "error", 
                    failure_code="PUSH_BLOCKED_CI_LITE"
                )
            else:
                self.state_store.update_status(session_id, "error", failure_code="PR_FAILED")
            return None
