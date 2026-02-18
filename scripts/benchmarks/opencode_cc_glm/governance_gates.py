#!/usr/bin/env python3
"""Shared governance gates (baseline + integrity) for provider adapters."""

from __future__ import annotations

import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path


def _run_git(worktree: Path, args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(worktree), *args],
        check=False,
        capture_output=True,
        text=True,
    )


@dataclass(frozen=True)
class BaselineGateResult:
    passed: bool
    reason_code: str
    worktree: str
    required_baseline: str
    runtime_commit: str | None
    details: str

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


@dataclass(frozen=True)
class IntegrityGateResult:
    passed: bool
    reason_code: str
    worktree: str
    branch: str
    branch_head: str | None
    reported_commit: str
    details: str

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


def baseline_gate(worktree: Path, required_baseline: str) -> BaselineGateResult:
    worktree = worktree.resolve()
    if not required_baseline:
        return BaselineGateResult(
            passed=False,
            reason_code="required_baseline_missing",
            worktree=str(worktree),
            required_baseline=required_baseline,
            runtime_commit=None,
            details="required baseline must be provided",
        )
    if not worktree.exists():
        return BaselineGateResult(
            passed=False,
            reason_code="worktree_missing",
            worktree=str(worktree),
            required_baseline=required_baseline,
            runtime_commit=None,
            details="worktree path does not exist",
        )
    if _run_git(worktree, ["rev-parse", "--git-dir"]).returncode != 0:
        return BaselineGateResult(
            passed=False,
            reason_code="not_a_git_repo",
            worktree=str(worktree),
            required_baseline=required_baseline,
            runtime_commit=None,
            details="target path is not a git repository",
        )

    runtime = _run_git(worktree, ["rev-parse", "HEAD"])
    runtime_commit = runtime.stdout.strip() if runtime.returncode == 0 else None
    if not runtime_commit:
        return BaselineGateResult(
            passed=False,
            reason_code="runtime_commit_missing",
            worktree=str(worktree),
            required_baseline=required_baseline,
            runtime_commit=None,
            details="failed to resolve runtime HEAD commit",
        )

    required_exists = _run_git(worktree, ["cat-file", "-e", f"{required_baseline}^{{commit}}"])
    if required_exists.returncode != 0:
        return BaselineGateResult(
            passed=False,
            reason_code="required_commit_missing",
            worktree=str(worktree),
            required_baseline=required_baseline,
            runtime_commit=runtime_commit,
            details="required baseline commit is not present in this repository",
        )

    ancestor = _run_git(worktree, ["merge-base", "--is-ancestor", required_baseline, runtime_commit])
    if ancestor.returncode == 0:
        return BaselineGateResult(
            passed=True,
            reason_code="baseline_ok",
            worktree=str(worktree),
            required_baseline=required_baseline,
            runtime_commit=runtime_commit,
            details="runtime commit meets required baseline",
        )
    return BaselineGateResult(
        passed=False,
        reason_code="baseline_not_met",
        worktree=str(worktree),
        required_baseline=required_baseline,
        runtime_commit=runtime_commit,
        details="runtime commit is behind required baseline",
    )


def integrity_gate(worktree: Path, reported_commit: str, branch: str | None = None) -> IntegrityGateResult:
    worktree = worktree.resolve()
    if not reported_commit:
        return IntegrityGateResult(
            passed=False,
            reason_code="reported_commit_missing",
            worktree=str(worktree),
            branch=branch or "",
            branch_head=None,
            reported_commit=reported_commit,
            details="reported commit must be provided",
        )
    if not worktree.exists():
        return IntegrityGateResult(
            passed=False,
            reason_code="worktree_missing",
            worktree=str(worktree),
            branch=branch or "",
            branch_head=None,
            reported_commit=reported_commit,
            details="worktree path does not exist",
        )
    if _run_git(worktree, ["rev-parse", "--git-dir"]).returncode != 0:
        return IntegrityGateResult(
            passed=False,
            reason_code="not_a_git_repo",
            worktree=str(worktree),
            branch=branch or "",
            branch_head=None,
            reported_commit=reported_commit,
            details="target path is not a git repository",
        )

    if not branch:
        proc = _run_git(worktree, ["rev-parse", "--abbrev-ref", "HEAD"])
        branch = proc.stdout.strip() if proc.returncode == 0 else ""
    if not branch:
        return IntegrityGateResult(
            passed=False,
            reason_code="branch_missing",
            worktree=str(worktree),
            branch="",
            branch_head=None,
            reported_commit=reported_commit,
            details="failed to resolve target branch",
        )

    head_proc = _run_git(worktree, ["rev-parse", branch])
    if head_proc.returncode != 0:
        return IntegrityGateResult(
            passed=False,
            reason_code="branch_head_missing",
            worktree=str(worktree),
            branch=branch,
            branch_head=None,
            reported_commit=reported_commit,
            details=f"failed to resolve branch head for {branch}",
        )
    branch_head = head_proc.stdout.strip()

    reported_exists = _run_git(worktree, ["cat-file", "-e", f"{reported_commit}^{{commit}}"])
    if reported_exists.returncode != 0:
        return IntegrityGateResult(
            passed=False,
            reason_code="reported_commit_not_found",
            worktree=str(worktree),
            branch=branch,
            branch_head=branch_head,
            reported_commit=reported_commit,
            details="reported commit does not exist in repository",
        )

    ancestor = _run_git(worktree, ["merge-base", "--is-ancestor", reported_commit, branch_head])
    if ancestor.returncode == 0:
        return IntegrityGateResult(
            passed=True,
            reason_code="integrity_ok",
            worktree=str(worktree),
            branch=branch,
            branch_head=branch_head,
            reported_commit=reported_commit,
            details="reported commit is ancestor of branch head",
        )

    return IntegrityGateResult(
        passed=False,
        reason_code="reported_not_ancestor",
        worktree=str(worktree),
        branch=branch,
        branch_head=branch_head,
        reported_commit=reported_commit,
        details="reported commit is not ancestor of branch head",
    )
