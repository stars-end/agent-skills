"""
dx-loop runner adapter - Governed integration with dx-runner

Provides start/check/report integration with dx-runner as the
canonical execution substrate.

Source of truth for task execution state is dx-runner report --format json.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional, Dict, Any, List
from pathlib import Path
import platform
import subprocess
import json
import shutil
from json import JSONDecoder, JSONDecodeError


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
        return self.state in ("exited_ok", "exited_err", "blocked", "no_op_success")
    
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


@dataclass
class RunnerStartResult:
    """Structured dx-runner start result for truthful operator handling."""

    ok: bool
    returncode: int
    stdout: str = ""
    stderr: str = ""
    reason_code: Optional[str] = None
    detail: Optional[str] = None
    command: List[str] = field(default_factory=list)


class RunnerAdapter:
    """
    Governed adapter for dx-runner integration
    
    All execution goes through this adapter, ensuring consistent
    use of dx-runner as the canonical substrate.
    """
    
    def __init__(
        self,
        provider: str = "opencode",
        beads_repo_path: Optional[Path] = None,
    ):
        self.provider = provider
        self.beads_repo_path = beads_repo_path or Path.home() / "bd"

    def _dx_runner_script_path(self) -> Path:
        """Resolve the canonical dx-runner script path."""
        script_path = Path(__file__).resolve().parents[2] / "dx-runner"
        resolved = script_path.resolve()
        return resolved if resolved.exists() else script_path

    def _preferred_bash(self) -> Optional[Path]:
        """Find a bash 4+ entrypoint suitable for dx-runner on macOS."""
        for candidate in (Path("/opt/homebrew/bin/bash"), Path("/usr/local/bin/bash")):
            if candidate.exists():
                return candidate
        return None

    def _build_dx_runner_command(self, args: List[str]) -> RunnerStartResult:
        """
        Build an invocation command that works across host shells.

        On macOS, force dx-runner through a modern bash instead of inheriting the
        system bash 3.2 shebang path.
        """
        script_path = self._dx_runner_script_path()
        dx_runner = str(script_path) if script_path.exists() else shutil.which("dx-runner")

        if not dx_runner:
            return RunnerStartResult(
                ok=False,
                returncode=127,
                reason_code="dx_runner_missing",
                detail="dx-runner command not found on PATH",
            )

        if platform.system() == "Darwin":
            bash_path = self._preferred_bash()
            if not bash_path:
                return RunnerStartResult(
                    ok=False,
                    returncode=2,
                    reason_code="dx_runner_shell_preflight_failed",
                    detail=(
                        "dx-runner requires bash >= 4 on macOS, but no Homebrew "
                        "bash was found at /opt/homebrew/bin/bash or "
                        "/usr/local/bin/bash"
                    ),
                    command=[dx_runner, *args],
                )
            return RunnerStartResult(
                ok=True,
                returncode=0,
                command=[str(bash_path), dx_runner, *args],
            )

        return RunnerStartResult(
            ok=True,
            returncode=0,
            command=[dx_runner, *args],
        )

    def _classify_start_failure(
        self,
        returncode: int,
        stdout: str,
        stderr: str,
    ) -> tuple[str, str]:
        """Convert dx-runner launch failures into stable operator-facing reason codes."""
        detail = stderr.strip() or stdout.strip() or f"dx-runner exited with rc={returncode}"
        combined = f"{stdout}\n{stderr}".lower()

        if "requires bash >= 4" in combined:
            return "dx_runner_shell_preflight_failed", detail
        if returncode == 21:
            return "dx_runner_preflight_failed", detail
        if returncode == 22:
            return "dx_runner_permission_denied", detail
        if returncode == 25:
            return "dx_runner_model_unavailable", detail
        if returncode == 26:
            return "dx_runner_provider_capacity_blocked", detail
        return "dx_runner_start_failed", detail

    def _run_dx_runner(
        self,
        args: List[str],
        *,
        timeout: int = 30,
    ) -> RunnerStartResult:
        """Run dx-runner with host-compatible invocation and structured failures."""
        cmd_result = self._build_dx_runner_command(args)
        if not cmd_result.ok:
            return cmd_result

        try:
            result = subprocess.run(
                cmd_result.command,
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=str(self.beads_repo_path),
            )
        except subprocess.TimeoutExpired:
            return RunnerStartResult(
                ok=False,
                returncode=124,
                reason_code="dx_runner_start_timeout",
                detail=f"dx-runner timed out after {timeout}s",
                command=cmd_result.command,
            )
        except FileNotFoundError:
            return RunnerStartResult(
                ok=False,
                returncode=127,
                reason_code="dx_runner_missing",
                detail="dx-runner command not found on PATH",
                command=cmd_result.command,
            )

        if result.returncode == 0:
            return RunnerStartResult(
                ok=True,
                returncode=0,
                stdout=result.stdout,
                stderr=result.stderr,
                command=cmd_result.command,
            )

        reason_code, detail = self._classify_start_failure(
            result.returncode,
            result.stdout,
            result.stderr,
        )
        return RunnerStartResult(
            ok=False,
            returncode=result.returncode,
            stdout=result.stdout,
            stderr=result.stderr,
            reason_code=reason_code,
            detail=detail,
            command=cmd_result.command,
        )

    @staticmethod
    def _extract_json_payload(output: str) -> Optional[Dict[str, Any]]:
        """
        Parse the first JSON object from stdout, ignoring banner/preamble text.
        """
        if not output:
            return None

        decoder = JSONDecoder()
        for idx, char in enumerate(output):
            if char != "{":
                continue
            try:
                parsed, _ = decoder.raw_decode(output[idx:])
            except JSONDecodeError:
                continue
            if isinstance(parsed, dict):
                return parsed
        return None

    def start(
        self,
        beads_id: str,
        prompt_file: Path,
        worktree: Optional[Path] = None,
        **kwargs,
    ) -> RunnerStartResult:
        """
        Start task via dx-runner

        Returns structured outcome for truthful operator handling.
        """
        args = [
            "start",
            "--beads", beads_id,
            "--provider", self.provider,
            "--prompt-file", str(prompt_file),
        ]

        if worktree:
            args.extend(["--worktree", str(worktree)])

        result = self._run_dx_runner(args, timeout=30)
        if result.ok:
            return result

        if result.reason_code == "dx_runner_start_timeout":
            task_state = self.check(beads_id)
            if task_state and task_state.state not in {"missing", "unknown"}:
                return RunnerStartResult(
                    ok=True,
                    returncode=0,
                    stdout=result.stdout,
                    stderr=result.stderr,
                    reason_code="dx_runner_start_timeout_handoff",
                    detail=(
                        f"dx-runner start timed out, but runner state is "
                        f"{task_state.state}"
                    ),
                    command=result.command,
                )

        return result
    
    def check(self, beads_id: str) -> Optional[RunnerTaskState]:
        """
        Check task state via dx-runner
        
        Source of truth is dx-runner check --json
        """
        result = self._run_dx_runner(
            ["check", "--beads", beads_id, "--json"],
            timeout=30,
        )

        data = self._extract_json_payload(result.stdout)
        if not data:
            return RunnerTaskState(beads_id=beads_id, state="missing")

        return RunnerTaskState(
            beads_id=beads_id,
            state=data.get("state", "unknown"),
            reason_code=data.get("reason_code"),
            exit_code=data.get("exit_code"),
            started_at=data.get("started_at"),
            duration_sec=data.get("duration_sec"),
            has_pr_artifacts=bool(data.get("pr_url") and data.get("pr_head_sha")),
            pr_url=data.get("pr_url"),
            pr_head_sha=data.get("pr_head_sha"),
        )
    
    def report(self, beads_id: str) -> Optional[Dict[str, Any]]:
        """
        Get detailed report via dx-runner
        
        Source of truth is dx-runner report --format json
        """
        result = self._run_dx_runner(
            ["report", "--beads", beads_id, "--format", "json"],
            timeout=30,
        )

        return self._extract_json_payload(result.stdout)
    
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
        
        transcript = self.extract_agent_output(beads_id)
        if transcript:
            pr_url = None
            pr_head_sha = None
            for line in reversed(transcript.splitlines()):
                line = line.strip()
                if line.startswith("PR_URL:"):
                    pr_url = line.split(":", 1)[1].strip()
                elif line.startswith("PR_HEAD_SHA:"):
                    pr_head_sha = line.split(":", 1)[1].strip()
                if pr_url and pr_head_sha:
                    return (pr_url, pr_head_sha)

        return None

    def extract_agent_output(self, beads_id: str) -> Optional[str]:
        """
        Recover agent-authored text from the dx-runner JSONL log stream.
        """
        log_path = Path(f"/tmp/dx-runner/{self.provider}/{beads_id}.log")
        if not log_path.exists():
            return None

        text_parts: List[str] = []
        try:
            for raw_line in log_path.read_text().splitlines():
                raw_line = raw_line.strip()
                if not raw_line or not raw_line.startswith("{"):
                    continue
                try:
                    event = json.loads(raw_line)
                except JSONDecodeError:
                    continue
                if event.get("type") != "text":
                    continue
                part = event.get("part", {})
                text = part.get("text")
                if text:
                    text_parts.append(str(text))
        except OSError:
            return None

        if not text_parts:
            return None
        return "\n\n".join(text_parts)

    def _read_raw_log(self, beads_id: str) -> Optional[str]:
        """Fallback raw log reader for legacy/plaintext log fixtures."""
        log_path = Path(f"/tmp/dx-runner/{self.provider}/{beads_id}.log")
        if not log_path.exists():
            return None
        try:
            return log_path.read_text()
        except OSError:
            return None

    def extract_review_verdict(self, beads_id: str) -> Optional[str]:
        """
        Extract review verdict from report or raw log output.

        Review prompts currently emit one of:
        - APPROVED: ...
        - REVISION_REQUIRED: ...
        - BLOCKED: ...
        """
        report_data = self.report(beads_id)
        if report_data and report_data.get("verdict"):
            return str(report_data["verdict"])

        transcript = self.extract_agent_output(beads_id)
        if not transcript:
            transcript = self._read_raw_log(beads_id)
        if not transcript:
            return None

        try:
            for line in reversed(transcript.splitlines()):
                line = line.strip()
                if line.startswith("APPROVED:"):
                    return line
                if line.startswith("REVISION_REQUIRED:"):
                    return line
                if line.startswith("BLOCKED:"):
                    return line
        except OSError:
            return None

        return None
    
    def stop(self, beads_id: str) -> bool:
        """Stop task via dx-runner"""
        result = self._run_dx_runner(["stop", "--beads", beads_id], timeout=30)
        return result.ok
