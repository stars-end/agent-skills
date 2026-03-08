"""
dx-loop runner adapter - Governed integration with dx-runner

Provides start/check/report integration with dx-runner as the
canonical execution substrate.

Source of truth for task execution state is dx-runner report --format json.
"""

from __future__ import annotations
from dataclasses import dataclass
from typing import Optional, Dict, Any
from pathlib import Path
import subprocess
import json


@dataclass
class RunnerTaskState:
    """State of a task in dx-runner"""
    beads_id: str
    state: str  # healthy, stalled, exited_ok, exited_err, blocked, missing
    reason_code: Optional[str] = None
    exit_code: Optional[int] = None
    started_at: Optional[str] = None
    duration_sec: Optional[int] = None
    has_pr_artifacts: bool = False
    pr_url: Optional[str] = None
    pr_head_sha: Optional[str] = None
    
    def is_complete(self) -> bool:
        """Check if task is complete (exited or blocked)"""
        return self.state in ("exited_ok", "exited_err", "blocked")
    
    def is_running(self) -> bool:
        """Check if task is still running"""
        return self.state in ("healthy", "stalled", "launching")
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "beads_id": self.beads_id,
            "state": self.state,
            "reason_code": self.reason_code,
            "exit_code": self.exit_code,
            "started_at": self.started_at,
            "duration_sec": self.duration_sec,
            "has_pr_artifacts": self.has_pr_artifacts,
            "pr_url": self.pr_url,
            "pr_head_sha": self.pr_head_sha,
        }


class RunnerAdapter:
    """
    Governed adapter for dx-runner integration
    
    All execution goes through this adapter, ensuring consistent
    use of dx-runner as the canonical substrate.
    """
    
    def __init__(self, provider: str = "opencode"):
        self.provider = provider
    
    def start(
        self,
        beads_id: str,
        prompt_file: Path,
        worktree: Optional[Path] = None,
        **kwargs,
    ) -> bool:
        """
        Start task via dx-runner
        
        Returns True if dispatch succeeded, False otherwise.
        """
        cmd = [
            "dx-runner", "start",
            "--beads", beads_id,
            "--provider", self.provider,
            "--prompt-file", str(prompt_file),
        ]
        
        if worktree:
            cmd.extend(["--worktree", str(worktree)])
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
            )
            
            # dx-runner returns 0 on success
            return result.returncode == 0
        
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            return False
    
    def check(self, beads_id: str) -> Optional[RunnerTaskState]:
        """
        Check task state via dx-runner
        
        Source of truth is dx-runner check --json
        """
        try:
            result = subprocess.run(
                ["dx-runner", "check", "--beads", beads_id, "--json"],
                capture_output=True,
                text=True,
                timeout=30,
            )
            
            if not result.stdout.strip():
                # Task not found
                return RunnerTaskState(beads_id=beads_id, state="missing")
            
            data = json.loads(result.stdout)
            
            state = RunnerTaskState(
                beads_id=beads_id,
                state=data.get("state", "unknown"),
                reason_code=data.get("reason_code"),
                exit_code=data.get("exit_code"),
                started_at=data.get("started_at"),
                duration_sec=data.get("duration_sec"),
            )
            
            return state
        
        except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
            return RunnerTaskState(beads_id=beads_id, state="missing")
    
    def report(self, beads_id: str) -> Optional[Dict[str, Any]]:
        """
        Get detailed report via dx-runner
        
        Source of truth is dx-runner report --format json
        """
        try:
            result = subprocess.run(
                ["dx-runner", "report", "--beads", beads_id, "--format", "json"],
                capture_output=True,
                text=True,
                timeout=30,
            )
            
            if result.returncode != 0 or not result.stdout.strip():
                return None
            
            return json.loads(result.stdout)
        
        except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
            return None
    
    def extract_pr_artifacts(self, beads_id: str) -> Optional[tuple[str, str]]:
        """
        Extract PR artifacts from dx-runner logs
        
        Returns (pr_url, pr_head_sha) if found, None otherwise.
        """
        report_data = self.report(beads_id)
        if not report_data:
            return None
        
        # Check if report has PR artifacts
        pr_url = report_data.get("pr_url")
        pr_head_sha = report_data.get("pr_head_sha")
        
        if pr_url and pr_head_sha:
            return (pr_url, pr_head_sha)
        
        # Fall back to reading log
        log_path = Path(f"/tmp/dx-runner/{self.provider}/{beads_id}.log")
        if not log_path.exists():
            return None
        
        try:
            log_content = log_path.read_text()
            
            # Extract PR_URL and PR_HEAD_SHA from log
            pr_url = None
            pr_head_sha = None
            
            for line in reversed(log_content.split('\n')):
                line = line.strip()
                if line.startswith('PR_URL:'):
                    pr_url = line.split(':', 1)[1].strip()
                elif line.startswith('PR_HEAD_SHA:'):
                    pr_head_sha = line.split(':', 1)[1].strip()
                
                if pr_url and pr_head_sha:
                    return (pr_url, pr_head_sha)
        
        except OSError:
            pass
        
        return None
    
    def stop(self, beads_id: str) -> bool:
        """Stop task via dx-runner"""
        try:
            result = subprocess.run(
                ["dx-runner", "stop", "--beads", beads_id],
                capture_output=True,
                text=True,
                timeout=30,
            )
            return result.returncode == 0
        
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return False
