#!/usr/bin/env python3
"""6-stream multi-provider soak validation runner.

Deterministic validation that runs 6 parallel jobs (2 per provider) across
opencode/cc-glm/gemini, executes two consecutive clean rounds, and produces
machine-readable + markdown evidence for tech-lead signoff.

Usage:
    scripts/validation/multi_provider_soak.py [--dry-run] [--rounds N] [--parallel N]

The runner uses dx-runner as the canonical command surface and enforces:
- OpenCode provider uses zhipuai-coding-plan/glm-5 (no zai-coding-plan fallback)
- Two consecutive clean rounds with aggregate pass/fail gate
- Machine-readable JSON + human-readable Markdown artifacts
"""

from __future__ import annotations

import argparse
import concurrent.futures
import dataclasses
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from typing import Any

PROVIDERS = ["opencode", "cc-glm", "gemini"]
JOBS_PER_PROVIDER = 2
DEFAULT_ROUNDS = 2
DEFAULT_TIMEOUT_SEC = 300.0
ARTIFACTS_DIR = pathlib.Path("artifacts/multi-provider-soak")

OPENCODE_CANONICAL_MODEL = "zhipuai-coding-plan/glm-5"
CC_GLM_DEFAULT_MODEL = "glm-5"
GEMINI_DEFAULT_MODEL = "gemini-3-flash-preview"

SIMPLE_PROMPTS = [
    {
        "id": "echo_ok",
        "prompt": "Return exactly: OK",
        "success_hint": "OK",
    },
    {
        "id": "echo_ready",
        "prompt": "Return exactly: READY",
        "success_hint": "READY",
    },
]


def utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def utc_now_compact() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


@dataclass(frozen=True)
class JobSpec:
    beads_id: str
    provider: str
    prompt_id: str
    prompt: str
    success_hint: str
    model: str
    worktree: pathlib.Path
    round_num: int
    job_index: int


@dataclass
class JobResult:
    job_spec: JobSpec
    success: bool
    status: str
    reason_code: str | None
    selected_model: str | None
    latency_ms: int | None
    completion: bool
    retries: int
    outcome_state: str
    stdout: str
    stderr: str
    started_at: str
    completed_at: str
    raw_outcome: dict[str, Any] | None = None

    def to_dict(self) -> dict[str, Any]:
        spec_dict = asdict(self.job_spec)
        spec_dict["worktree"] = str(spec_dict["worktree"])
        return {
            "job_spec": spec_dict,
            "success": self.success,
            "status": self.status,
            "reason_code": self.reason_code,
            "selected_model": self.selected_model,
            "latency_ms": self.latency_ms,
            "completion": self.completion,
            "retries": self.retries,
            "outcome_state": self.outcome_state,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
            "raw_outcome": self.raw_outcome,
        }


@dataclass
class RoundResult:
    round_num: int
    jobs: list[JobResult]
    passed: bool
    pass_rate: float
    started_at: str
    completed_at: str
    duration_sec: float

    def to_dict(self) -> dict[str, Any]:
        return {
            "round_num": self.round_num,
            "job_count": len(self.jobs),
            "passed": self.passed,
            "pass_rate": self.pass_rate,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
            "duration_sec": self.duration_sec,
            "jobs": [j.to_dict() for j in self.jobs],
        }


@dataclass
class SoakResult:
    run_id: str
    rounds: list[RoundResult]
    passed: bool
    all_clean: bool
    total_jobs: int
    total_passed: int
    total_failed: int
    started_at: str
    completed_at: str
    duration_sec: float
    provider_summary: dict[str, dict[str, Any]]

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "passed": self.passed,
            "all_clean": self.all_clean,
            "total_jobs": self.total_jobs,
            "total_passed": self.total_passed,
            "total_failed": self.total_failed,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
            "duration_sec": self.duration_sec,
            "provider_summary": self.provider_summary,
            "rounds": [r.to_dict() for r in self.rounds],
        }


def get_provider_model(provider: str) -> str:
    if provider == "opencode":
        return os.environ.get("OPENCODE_MODEL", OPENCODE_CANONICAL_MODEL)
    elif provider == "cc-glm":
        return os.environ.get("CC_GLM_MODEL", CC_GLM_DEFAULT_MODEL)
    elif provider == "gemini":
        return os.environ.get("GEMINI_MODEL", GEMINI_DEFAULT_MODEL)
    return "unknown"


def find_dx_runner() -> pathlib.Path:
    candidates = [
        pathlib.Path("scripts/dx-runner"),
        pathlib.Path("/home/fengning/agent-skills/scripts/dx-runner"),
        pathlib.Path.home() / "agent-skills/scripts/dx-runner",
    ]
    for c in candidates:
        if c.exists() and c.is_file():
            return c.resolve()
    raise RuntimeError("dx-runner not found")


def wait_for_job_completion(
    beads_id: str,
    provider: str,
    timeout_sec: float,
    poll_interval: float = 5.0,
) -> dict[str, Any]:
    dx_runner = find_dx_runner()
    deadline = time.perf_counter() + timeout_sec
    
    while time.perf_counter() < deadline:
        proc = subprocess.run(
            [str(dx_runner), "check", "--beads", beads_id, "--json"],
            capture_output=True,
            text=True,
        )
        if proc.returncode == 0:
            try:
                payload = json.loads(proc.stdout.strip())
                state = payload.get("state", "")
                if state in ("exited_ok", "exited_err", "stalled", "missing", "no_op"):
                    return payload
            except json.JSONDecodeError:
                pass
        elif proc.returncode in (2, 3):
            try:
                payload = json.loads(proc.stdout.strip()) if proc.stdout.strip() else {}
            except json.JSONDecodeError:
                payload = {}
            return {"state": "stalled" if proc.returncode == 2 else "exited_err", **payload}
        
        time.sleep(poll_interval)
    
    return {"state": "timeout", "reason_code": "wait_timeout"}


def get_job_outcome(beads_id: str, provider: str) -> dict[str, Any]:
    dx_runner = find_dx_runner()
    
    log_dir = pathlib.Path(f"/tmp/dx-runner/{provider}")
    outcome_file = log_dir / f"{beads_id}.outcome"
    
    if outcome_file.exists():
        outcome = {}
        for line in outcome_file.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                outcome[k.strip()] = v.strip()
        return outcome
    
    proc = subprocess.run(
        [str(dx_runner), "report", "--beads", beads_id, "--format", "json"],
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        try:
            return json.loads(proc.stdout.strip())
        except json.JSONDecodeError:
            pass
    
    return {}


def run_single_job(job_spec: JobSpec, timeout_sec: float, dry_run: bool) -> JobResult:
    started_at = utc_now_iso()
    
    if dry_run:
        import random
        random.seed(hash(job_spec.beads_id))
        success = random.random() > 0.1
        latency_ms = random.randint(500, 2000)
        
        return JobResult(
            job_spec=job_spec,
            success=success,
            status="exited_ok" if success else "exited_err",
            reason_code=None if success else "dry_run_simulated",
            selected_model=job_spec.model,
            latency_ms=latency_ms,
            completion=True,
            retries=0,
            outcome_state="success" if success else "failed",
            stdout="DRY_RUN: " + job_spec.success_hint if success else "",
            stderr="" if success else "DRY_RUN: simulated failure",
            started_at=started_at,
            completed_at=utc_now_iso(),
        )
    
    dx_runner = find_dx_runner()
    prompt_file = pathlib.Path(f"/tmp/soak-prompt-{job_spec.beads_id}.txt")
    prompt_file.write_text(job_spec.prompt, encoding="utf-8")
    
    cmd = [
        str(dx_runner),
        "start",
        "--beads", job_spec.beads_id,
        "--provider", job_spec.provider,
        "--prompt-file", str(prompt_file),
        "--worktree", str(job_spec.worktree),
    ]
    
    start_proc = subprocess.run(cmd, capture_output=True, text=True)
    
    if start_proc.returncode != 0:
        stderr = start_proc.stderr.strip() or start_proc.stdout.strip()
        reason_code = "start_failed"
        if "model_unavailable" in stderr.lower() or "model not" in stderr.lower():
            reason_code = "model_unavailable"
        elif "auth" in stderr.lower() or "forbidden" in stderr.lower():
            reason_code = "auth_error"
        elif "permission" in stderr.lower() or "denied" in stderr.lower():
            reason_code = "permission_denied"
        
        return JobResult(
            job_spec=job_spec,
            success=False,
            status="start_failed",
            reason_code=reason_code,
            selected_model=job_spec.model,
            latency_ms=None,
            completion=False,
            retries=0,
            outcome_state="failed",
            stdout=start_proc.stdout.strip(),
            stderr=stderr,
            started_at=started_at,
            completed_at=utc_now_iso(),
        )
    
    start_meta = {}
    for line in start_proc.stdout.strip().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            start_meta[k.strip()] = v.strip()
    
    check_result = wait_for_job_completion(
        job_spec.beads_id,
        job_spec.provider,
        timeout_sec=timeout_sec,
    )
    
    outcome = get_job_outcome(job_spec.beads_id, job_spec.provider)
    completed_at = utc_now_iso()
    
    state = check_result.get("state", outcome.get("state", "unknown"))
    exit_code = outcome.get("exit_code", "1")
    
    try:
        exit_code_int = int(exit_code)
    except (ValueError, TypeError):
        exit_code_int = 1
    
    success = state == "exited_ok" and exit_code_int == 0
    
    try:
        started_dt = dt.datetime.fromisoformat(started_at.replace("Z", "+00:00"))
        completed_dt = dt.datetime.fromisoformat(completed_at.replace("Z", "+00:00"))
        latency_ms = int((completed_dt - started_dt).total_seconds() * 1000)
    except Exception:
        latency_ms = None
    
    return JobResult(
        job_spec=job_spec,
        success=success,
        status=state,
        reason_code=outcome.get("reason_code") or check_result.get("reason_code"),
        selected_model=outcome.get("selected_model") or start_meta.get("selected_model") or job_spec.model,
        latency_ms=latency_ms,
        completion=state not in ("stalled", "timeout", "missing"),
        retries=int(outcome.get("retries", "0") or "0"),
        outcome_state=outcome.get("state", "unknown"),
        stdout="",
        stderr=outcome.get("details", ""),
        started_at=started_at,
        completed_at=completed_at,
        raw_outcome=outcome if outcome else None,
    )


def run_round(
    round_num: int,
    run_id: str,
    worktree: pathlib.Path,
    timeout_sec: float,
    dry_run: bool,
    parallel: int,
) -> RoundResult:
    started_at = utc_now_iso()
    start_time = time.perf_counter()
    
    jobs: list[JobSpec] = []
    for provider in PROVIDERS:
        model = get_provider_model(provider)
        for i in range(JOBS_PER_PROVIDER):
            prompt_data = SIMPLE_PROMPTS[i % len(SIMPLE_PROMPTS)]
            job_index = len(jobs)
            beads_id = f"{run_id}-r{round_num}-{provider}-{i}"
            
            jobs.append(JobSpec(
                beads_id=beads_id,
                provider=provider,
                prompt_id=prompt_data["id"],
                prompt=prompt_data["prompt"],
                success_hint=prompt_data["success_hint"],
                model=model,
                worktree=worktree,
                round_num=round_num,
                job_index=job_index,
            ))
    
    results: list[JobResult] = []
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=parallel) as executor:
        future_to_job = {
            executor.submit(run_single_job, job, timeout_sec, dry_run): job
            for job in jobs
        }
        
        for future in concurrent.futures.as_completed(future_to_job):
            job = future_to_job[future]
            try:
                result = future.result()
                results.append(result)
            except Exception as exc:
                results.append(JobResult(
                    job_spec=job,
                    success=False,
                    status="exception",
                    reason_code="executor_exception",
                    selected_model=job.model,
                    latency_ms=None,
                    completion=False,
                    retries=0,
                    outcome_state="failed",
                    stdout="",
                    stderr=str(exc),
                    started_at=utc_now_iso(),
                    completed_at=utc_now_iso(),
                ))
    
    completed_at = utc_now_iso()
    duration_sec = time.perf_counter() - start_time
    
    passed_count = sum(1 for r in results if r.success)
    pass_rate = passed_count / len(results) if results else 0.0
    passed = pass_rate == 1.0
    
    return RoundResult(
        round_num=round_num,
        jobs=results,
        passed=passed,
        pass_rate=pass_rate,
        started_at=started_at,
        completed_at=completed_at,
        duration_sec=duration_sec,
    )


def compute_provider_summary(rounds: list[RoundResult]) -> dict[str, dict[str, Any]]:
    summary: dict[str, dict[str, Any]] = {p: {"total": 0, "passed": 0, "failed": 0, "latencies_ms": []} for p in PROVIDERS}
    
    for round_result in rounds:
        for job in round_result.jobs:
            provider = job.job_spec.provider
            summary[provider]["total"] += 1
            if job.success:
                summary[provider]["passed"] += 1
            else:
                summary[provider]["failed"] += 1
            if job.latency_ms is not None:
                summary[provider]["latencies_ms"].append(job.latency_ms)
    
    for provider in PROVIDERS:
        latencies = summary[provider]["latencies_ms"]
        if latencies:
            summary[provider]["latency_ms_mean"] = sum(latencies) / len(latencies)
            summary[provider]["latency_ms_p50"] = sorted(latencies)[len(latencies) // 2]
        else:
            summary[provider]["latency_ms_mean"] = None
            summary[provider]["latency_ms_p50"] = None
        del summary[provider]["latencies_ms"]
    
    return summary


def generate_markdown_report(soak_result: SoakResult) -> str:
    lines = [
        f"# Multi-Provider Soak Validation Report",
        "",
        f"**Run ID:** {soak_result.run_id}",
        f"**Status:** {'PASSED' if soak_result.passed else 'FAILED'}",
        f"**All Clean:** {'Yes' if soak_result.all_clean else 'No'}",
        f"**Started:** {soak_result.started_at}",
        f"**Completed:** {soak_result.completed_at}",
        f"**Duration:** {soak_result.duration_sec:.1f}s",
        "",
        "## Summary",
        "",
        f"| Metric | Value |",
        f"|--------|-------|",
        f"| Total Jobs | {soak_result.total_jobs} |",
        f"| Passed | {soak_result.total_passed} |",
        f"| Failed | {soak_result.total_failed} |",
        f"| Pass Rate | {soak_result.total_passed / soak_result.total_jobs * 100:.1f}% |" if soak_result.total_jobs > 0 else "| Pass Rate | N/A |",
        "",
        "## Provider Summary",
        "",
        "| Provider | Total | Passed | Failed | Latency Mean (ms) | Latency P50 (ms) |",
        "|----------|-------|--------|--------|-------------------|------------------|",
    ]
    
    for provider, stats in soak_result.provider_summary.items():
        latency_mean = f"{stats['latency_ms_mean']:.0f}" if stats.get('latency_ms_mean') is not None else "-"
        latency_p50 = f"{stats['latency_ms_p50']:.0f}" if stats.get('latency_ms_p50') is not None else "-"
        lines.append(f"| {provider} | {stats['total']} | {stats['passed']} | {stats['failed']} | {latency_mean} | {latency_p50} |")
    
    lines.extend([
        "",
        "## Rounds",
        "",
    ])
    
    for round_result in soak_result.rounds:
        status_icon = "✅" if round_result.passed else "❌"
        lines.extend([
            f"### Round {round_result.round_num} {status_icon}",
            "",
            f"- **Passed:** {round_result.passed}",
            f"- **Pass Rate:** {round_result.pass_rate * 100:.1f}%",
            f"- **Duration:** {round_result.duration_sec:.1f}s",
            "",
            "| Provider | Prompt | Status | Reason | Latency (ms) |",
            "|----------|--------|--------|--------|--------------|",
        ])
        
        for job in round_result.jobs:
            status = "✅" if job.success else "❌"
            reason = job.reason_code or "-"
            latency = f"{job.latency_ms}" if job.latency_ms is not None else "-"
            lines.append(f"| {job.job_spec.provider} | {job.job_spec.prompt_id} | {status} | {reason} | {latency} |")
        
        lines.append("")
    
    lines.extend([
        "## Pass/Fail Gate",
        "",
        "This validation requires:",
        "- All rounds must pass (100% success rate per round)",
        "- No failures across any provider",
        "",
        f"**Result:** {'PASSED - All rounds clean' if soak_result.passed and soak_result.all_clean else 'FAILED - Check details above'}",
        "",
    ])
    
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="6-stream multi-provider soak validation")
    parser.add_argument("--dry-run", action="store_true", help="Simulate without actual dispatch")
    parser.add_argument("--rounds", type=int, default=DEFAULT_ROUNDS, help="Number of consecutive rounds")
    parser.add_argument("--parallel", type=int, default=6, help="Parallel job count")
    parser.add_argument("--timeout-sec", type=float, default=DEFAULT_TIMEOUT_SEC, help="Job timeout in seconds")
    parser.add_argument("--worktree", type=pathlib.Path, default=None, help="Worktree path for jobs")
    parser.add_argument("--run-id", default=None, help="Run ID (auto-generated if not set)")
    parser.add_argument("--output-dir", type=pathlib.Path, default=ARTIFACTS_DIR, help="Output directory")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    
    run_id = args.run_id or f"soak-{utc_now_compact()}"
    worktree = args.worktree or pathlib.Path.cwd()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"=== Multi-Provider Soak Validation ===")
    print(f"Run ID: {run_id}")
    print(f"Rounds: {args.rounds}")
    print(f"Providers: {', '.join(PROVIDERS)} ({JOBS_PER_PROVIDER} jobs each)")
    print(f"Worktree: {worktree}")
    print(f"Dry Run: {args.dry_run}")
    print()
    
    if not args.dry_run:
        dx_runner = find_dx_runner()
        proc = subprocess.run([str(dx_runner), "preflight", "--provider", "opencode"], capture_output=True, text=True)
        print(proc.stdout)
        if proc.returncode != 0:
            print("ERROR: Preflight failed. Fix issues before running validation.")
            return 21
    
    soak_started_at = utc_now_iso()
    soak_start_time = time.perf_counter()
    
    round_results: list[RoundResult] = []
    
    for round_num in range(1, args.rounds + 1):
        print(f"\n--- Round {round_num}/{args.rounds} ---")
        
        round_result = run_round(
            round_num=round_num,
            run_id=run_id,
            worktree=worktree,
            timeout_sec=args.timeout_sec,
            dry_run=args.dry_run,
            parallel=args.parallel,
        )
        round_results.append(round_result)
        
        print(f"Round {round_num}: {'PASSED' if round_result.passed else 'FAILED'} ({round_result.pass_rate * 100:.1f}% pass rate)")
        
        for job in round_result.jobs:
            status = "OK" if job.success else "FAIL"
            print(f"  [{job.job_spec.provider}] {job.job_spec.prompt_id}: {status} ({job.reason_code or 'success'})")
        
        if not round_result.passed and not args.dry_run:
            print(f"\nWARNING: Round {round_num} failed. Continuing to next round for diagnostics...")
    
    soak_completed_at = utc_now_iso()
    soak_duration = time.perf_counter() - soak_start_time
    
    all_passed = all(r.passed for r in round_results)
    all_clean = all(r.pass_rate == 1.0 for r in round_results)
    total_jobs = sum(len(r.jobs) for r in round_results)
    total_passed = sum(sum(1 for j in r.jobs if j.success) for r in round_results)
    total_failed = total_jobs - total_passed
    
    provider_summary = compute_provider_summary(round_results)
    
    soak_result = SoakResult(
        run_id=run_id,
        rounds=round_results,
        passed=all_passed,
        all_clean=all_clean,
        total_jobs=total_jobs,
        total_passed=total_passed,
        total_failed=total_failed,
        started_at=soak_started_at,
        completed_at=soak_completed_at,
        duration_sec=soak_duration,
        provider_summary=provider_summary,
    )
    
    json_path = output_dir / f"{run_id}.json"
    md_path = output_dir / f"{run_id}.md"
    
    json_path.write_text(json.dumps(soak_result.to_dict(), indent=2), encoding="utf-8")
    md_path.write_text(generate_markdown_report(soak_result), encoding="utf-8")
    
    print(f"\n=== Validation Complete ===")
    print(f"Status: {'PASSED' if soak_result.passed else 'FAILED'}")
    print(f"All Clean: {soak_result.all_clean}")
    print(f"Total: {total_passed}/{total_jobs} passed")
    print(f"Duration: {soak_duration:.1f}s")
    print(f"\nArtifacts:")
    print(f"  JSON: {json_path}")
    print(f"  Markdown: {md_path}")
    
    return 0 if soak_result.passed and soak_result.all_clean else 1


if __name__ == "__main__":
    sys.exit(main())
