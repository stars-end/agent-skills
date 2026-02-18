#!/usr/bin/env python
"""
No-Op Execution Gate - Detects and aborts runs with no mutations.

Addresses bd-cbsb.17: No-op execution gate with heartbeat tracking.
"""

from __future__ import annotations

import subprocess
import time
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any


class ExecutionStatus(Enum):
    ACTIVE = "active"
    NO_OP_DETECTED = "no_op_detected"
    TOOL_HUNG = "tool_hung"
    COMPLETED = "completed"
    ERROR = "error"
    ABORTED = "aborted"


@dataclass
class HeartbeatRecord:
    timestamp: str
    tool_name: str | None = None
    mutation_detected: bool = False
    files_changed: int = 0
    commits_made: int = 0
    tokens_generated: int = 0


@dataclass
class ExecutionGateResult:
    status: ExecutionStatus
    session_id: str
    worktree_path: str
    elapsed_seconds: int
    heartbeat_count: int = 0
    last_heartbeat: str | None = None
    last_mutation: str | None = None
    mutations_total: int = 0
    no_op_threshold_seconds: int = 300
    recommendation: str | None = None
    error_detail: str | None = None
    heartbeat_history: list[HeartbeatRecord] = field(default_factory=list)


class NoOpExecutionGate:
    """
    Monitors OpenCode sessions for no-op execution.

    A "no-op" run is defined as:
    - Active token streaming for > threshold seconds
    - No file mutations detected
    - No commits made
    - No explicit failure/termination
    """

    DEFAULT_NO_OP_THRESHOLD_SECONDS = 300  # 5 minutes
    DEFAULT_POLL_INTERVAL_SECONDS = 30

    def __init__(
        self,
        worktree_path: str,
        no_op_threshold_seconds: int | None = None,
        poll_interval_seconds: int | None = None,
    ):
        self.worktree_path = Path(worktree_path)
        self.no_op_threshold = (
            no_op_threshold_seconds or self.DEFAULT_NO_OP_THRESHOLD_SECONDS
        )
        self.poll_interval = poll_interval_seconds or self.DEFAULT_POLL_INTERVAL_SECONDS
        self.heartbeat_history: list[HeartbeatRecord] = []
        self._last_git_hash: str | None = None
        self._start_time: float | None = None
        self._last_mutation_time: float | None = None

    def start(self) -> None:
        """Initialize monitoring."""
        self._start_time = time.time()
        self._last_mutation_time = time.time()
        self._last_git_hash = self._get_current_git_hash()
        self._record_heartbeat(mutation_detected=True)

    def _get_current_git_hash(self) -> str | None:
        """Get current git HEAD hash."""
        try:
            result = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                capture_output=True,
                text=True,
                cwd=self.worktree_path,
                timeout=10,
            )
            if result.returncode == 0:
                return result.stdout.strip()[:12]
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        return None

    def _get_files_changed(self) -> int:
        """Count number of changed files (unstaged + staged)."""
        try:
            result = subprocess.run(
                ["git", "status", "--porcelain"],
                capture_output=True,
                text=True,
                cwd=self.worktree_path,
                timeout=10,
            )
            if result.returncode == 0:
                return len([l for l in result.stdout.strip().split("\n") if l])
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        return 0

    def _get_commits_made(self) -> int:
        """Count commits since monitoring started."""
        if not self._last_git_hash:
            return 0
        try:
            result = subprocess.run(
                ["git", "rev-list", "--count", f"{self._last_git_hash}..HEAD"],
                capture_output=True,
                text=True,
                cwd=self.worktree_path,
                timeout=10,
            )
            if result.returncode == 0:
                return int(result.stdout.strip())
        except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
            pass
        return 0

    def _record_heartbeat(
        self,
        tool_name: str | None = None,
        tokens_generated: int = 0,
        mutation_detected: bool = False,
    ) -> HeartbeatRecord:
        """Record a heartbeat and return it."""
        current_hash = self._get_current_git_hash()
        files_changed = self._get_files_changed()
        commits_made = self._get_commits_made()

        if mutation_detected is False:
            mutation_detected = (
                current_hash != self._last_git_hash
                or files_changed > 0
                or commits_made > 0
            )

        if mutation_detected:
            self._last_mutation_time = time.time()
            self._last_git_hash = current_hash

        record = HeartbeatRecord(
            timestamp=datetime.utcnow().isoformat(),
            tool_name=tool_name,
            mutation_detected=mutation_detected,
            files_changed=files_changed,
            commits_made=commits_made,
            tokens_generated=tokens_generated,
        )
        self.heartbeat_history.append(record)
        return record

    def check(self, tool_name: str | None = None) -> ExecutionGateResult:
        """
        Check execution status and detect no-op runs.

        Returns ExecutionGateResult with current status.
        """
        if self._start_time is None:
            self.start()

        now = time.time()
        elapsed = int(now - (self._start_time or now))

        heartbeat = self._record_heartbeat(tool_name=tool_name)

        time_since_mutation = now - (self._last_mutation_time or now)
        is_no_op = (
            time_since_mutation > self.no_op_threshold
            and len(self.heartbeat_history) >= 3
        )

        if is_no_op:
            status = ExecutionStatus.NO_OP_DETECTED
            recommendation = (
                f"No mutations detected for {int(time_since_mutation)}s. "
                "Consider: 1) Abort and retry with different prompt, "
                "2) Escalate to fallback model, 3) Manual intervention."
            )
        else:
            status = ExecutionStatus.ACTIVE
            recommendation = None

        return ExecutionGateResult(
            status=status,
            session_id="",
            worktree_path=str(self.worktree_path),
            elapsed_seconds=elapsed,
            heartbeat_count=len(self.heartbeat_history),
            last_heartbeat=heartbeat.timestamp,
            last_mutation=datetime.utcfromtimestamp(
                self._last_mutation_time or 0
            ).isoformat()
            if self._last_mutation_time
            else None,
            mutations_total=sum(
                1 for h in self.heartbeat_history if h.mutation_detected
            ),
            no_op_threshold_seconds=self.no_op_threshold,
            recommendation=recommendation,
            heartbeat_history=self.heartbeat_history[-10:],
        )

    def should_abort(self) -> tuple[bool, str | None]:
        """
        Check if execution should be aborted due to no-op.

        Returns (should_abort, reason).
        """
        result = self.check()
        if result.status == ExecutionStatus.NO_OP_DETECTED:
            return True, result.recommendation
        return False, None


def classify_execution_failure(
    elapsed_seconds: int,
    heartbeat_count: int,
    mutations_total: int,
    last_tool_status: str | None = None,
) -> tuple[ExecutionStatus, str]:
    """
    Classify execution failure type.

    Returns (status, failure_code) tuple.
    """
    if mutations_total > 0:
        return ExecutionStatus.ACTIVE, "mutations_detected"

    if last_tool_status == "error":
        return ExecutionStatus.ERROR, "tool_error"

    if heartbeat_count == 0:
        return ExecutionStatus.ERROR, "no_heartbeat"

    if elapsed_seconds > 300 and mutations_total == 0:
        return ExecutionStatus.NO_OP_DETECTED, "no_op_run"

    if elapsed_seconds > 600:
        return ExecutionStatus.TOOL_HUNG, "timeout_no_progress"

    return ExecutionStatus.ACTIVE, "unknown"


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: noop_gate.py <worktree_path> [--threshold SECONDS]")
        sys.exit(1)

    worktree = sys.argv[1]
    threshold = 300

    if "--threshold" in sys.argv:
        idx = sys.argv.index("--threshold")
        if idx + 1 < len(sys.argv):
            threshold = int(sys.argv[idx + 1])

    gate = NoOpExecutionGate(worktree, no_op_threshold_seconds=threshold)

    print(f"No-Op Gate initialized for: {worktree}")
    print(f"Threshold: {threshold}s")

    result = gate.check()

    print(f"\nStatus: {result.status.value}")
    print(f"Elapsed: {result.elapsed_seconds}s")
    print(f"Heartbeats: {result.heartbeat_count}")
    print(f"Mutations: {result.mutations_total}")
    if result.recommendation:
        print(f"Recommendation: {result.recommendation}")
