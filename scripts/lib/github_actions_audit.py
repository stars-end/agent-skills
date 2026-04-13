#!/usr/bin/env python3
"""Cross-repo GitHub Actions failure collector with active/stale classification."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
from collections import defaultdict
from pathlib import Path
from typing import Any, Callable


ANSI_ESCAPE_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")
SHA_RE = re.compile(r"\b[0-9a-f]{7,40}\b", flags=re.IGNORECASE)
LONG_NUM_RE = re.compile(r"\d{3,}")
WS_RE = re.compile(r"\s+")

SIGNATURE_PATTERNS = [
    re.compile(r"process completed with exit code \d+", flags=re.IGNORECASE),
    re.compile(r"\b(traceback|assertionerror|modulenotfounderror|typeerror|valueerror|runtimeerror)\b", flags=re.IGNORECASE),
    re.compile(r"\b(error|failed|failure|panic:|permission denied|no such file|npm err!|pnpm)\b", flags=re.IGNORECASE),
]


def utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_iso(ts: str | None) -> dt.datetime | None:
    if not ts:
        return None
    try:
        return dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def normalize_signature(text: str) -> str:
    value = text.strip().lower()
    value = SHA_RE.sub("<sha>", value)
    value = LONG_NUM_RE.sub("<n>", value)
    value = WS_RE.sub(" ", value)
    return value[:220]


def sanitize_log_text(text: str) -> list[str]:
    if not text:
        return []
    clean = ANSI_ESCAPE_RE.sub("", text)
    lines = [line.strip() for line in clean.splitlines()]
    return [line for line in lines if line]


def extract_signature(log_text: str, fallback: str) -> tuple[str, list[str]]:
    lines = sanitize_log_text(log_text)
    evidence: list[str] = []
    for line in lines:
        lowered = line.lower()
        if lowered.startswith("##[") or lowered.startswith("## "):
            continue
        for pattern in SIGNATURE_PATTERNS:
            if pattern.search(line):
                evidence.append(line[:280])
                signature = line[:180]
                return signature, evidence
    if lines:
        evidence.append(lines[0][:280])
    return fallback, evidence


def job_failure_fallback_signature(job: dict[str, Any], workflow: str) -> tuple[str, list[str]]:
    job_name = job.get("name") or workflow
    steps = job.get("steps") or []
    if isinstance(steps, list):
        for step in steps:
            if not isinstance(step, dict):
                continue
            conclusion = (step.get("conclusion") or "").lower()
            if conclusion and conclusion != "success":
                step_name = step.get("name") or "unknown-step"
                return (
                    f"step '{step_name}' failed",
                    [f"job={job_name}", f"step={step_name}", f"step_conclusion={conclusion}"],
                )
    conclusion = (job.get("conclusion") or "failure").lower()
    return (f"{job_name} failed", [f"job={job_name}", f"job_conclusion={conclusion}"])


def run_gh_json(args: list[str]) -> dict[str, Any]:
    command = ["gh", *args]
    try:
        proc = subprocess.run(command, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return {"ok": False, "error_code": "gh_missing", "message": "gh CLI not found", "stderr": ""}

    if proc.returncode != 0:
        return {
            "ok": False,
            "error_code": "gh_command_failed",
            "message": "gh command failed",
            "stderr": (proc.stderr or proc.stdout or "").strip()[:800],
            "command": command,
        }

    try:
        parsed = json.loads(proc.stdout or "null")
    except json.JSONDecodeError:
        return {
            "ok": False,
            "error_code": "gh_invalid_json",
            "message": "gh command returned invalid JSON",
            "stderr": (proc.stderr or "").strip()[:800],
            "command": command,
        }
    return {"ok": True, "data": parsed}


def run_gh_text(args: list[str]) -> dict[str, Any]:
    command = ["gh", *args]
    try:
        proc = subprocess.run(command, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        return {"ok": False, "error_code": "gh_missing", "message": "gh CLI not found", "stderr": ""}

    if proc.returncode != 0:
        return {
            "ok": False,
            "error_code": "gh_command_failed",
            "message": "gh command failed",
            "stderr": (proc.stderr or proc.stdout or "").strip()[:800],
            "command": command,
        }
    return {"ok": True, "data": proc.stdout}


def classify_group(group: dict[str, Any], repo_recent_runs: list[dict[str, Any]]) -> dict[str, Any]:
    workflow = group["workflow"]
    branch = group.get("head_branch") or ""
    last_seen_ts = parse_iso(group.get("last_seen"))
    candidates: list[dict[str, Any]] = []
    for run in repo_recent_runs:
        if run.get("workflowName") != workflow:
            continue
        run_branch = run.get("headBranch") or ""
        if branch and run_branch and run_branch != branch:
            continue
        candidates.append(run)

    candidates.sort(key=lambda run: parse_iso(run.get("createdAt")) or dt.datetime.min.replace(tzinfo=dt.timezone.utc), reverse=True)
    newest = candidates[0] if candidates else None
    newer_success = None
    if last_seen_ts:
        for run in candidates:
            created_ts = parse_iso(run.get("createdAt"))
            if not created_ts or created_ts <= last_seen_ts:
                continue
            if (run.get("conclusion") or "").lower() == "success":
                newer_success = run
                break

    if newer_success:
        return {
            "status": "stale",
            "reason": "newer_success_run",
            "reference_run": {
                "run_id": newer_success.get("databaseId"),
                "run_url": f"https://github.com/{group['repo']}/actions/runs/{newer_success.get('databaseId')}",
                "conclusion": newer_success.get("conclusion"),
                "created_at": newer_success.get("createdAt"),
            },
        }

    if newest:
        newest_conclusion = (newest.get("conclusion") or "").lower()
        status = "active"
        reason = "latest_run_not_success"
        if newest_conclusion == "success":
            reason = "latest_success_not_newer"
        return {
            "status": status,
            "reason": reason,
            "reference_run": {
                "run_id": newest.get("databaseId"),
                "run_url": f"https://github.com/{group['repo']}/actions/runs/{newest.get('databaseId')}",
                "conclusion": newest.get("conclusion"),
                "created_at": newest.get("createdAt"),
            },
        }

    return {
        "status": "active",
        "reason": "no_recent_run_data",
        "reference_run": None,
    }


def build_report(
    repos: list[str],
    failed_run_limit: int,
    recent_run_limit: int,
    gh_json_runner: Callable[[list[str]], dict[str, Any]] = run_gh_json,
    gh_text_runner: Callable[[list[str]], dict[str, Any]] = run_gh_text,
) -> dict[str, Any]:
    repo_statuses: list[dict[str, Any]] = []
    repo_errors: list[dict[str, Any]] = []
    grouped: dict[tuple[str, str, str, str], dict[str, Any]] = {}
    recent_runs_by_repo: dict[str, list[dict[str, Any]]] = defaultdict(list)

    for repo in repos:
        repo_entry = {"repo": repo, "status": "ok", "failed_runs_fetched": 0, "recent_runs_fetched": 0}
        fail_runs_result = gh_json_runner(
            [
                "run",
                "list",
                "--repo",
                repo,
                "--status",
                "failure",
                "--limit",
                str(failed_run_limit),
                "--json",
                "databaseId,workflowName,headBranch,headSha,createdAt,displayTitle,event,conclusion",
            ]
        )
        if not fail_runs_result.get("ok"):
            repo_entry["status"] = "error"
            error_rec = {
                "repo": repo,
                "stage": "run_list_failures",
                "error_code": fail_runs_result.get("error_code", "unknown_error"),
                "message": fail_runs_result.get("message", "failed to fetch failed runs"),
                "stderr": fail_runs_result.get("stderr", ""),
            }
            repo_entry["error"] = error_rec
            repo_errors.append(error_rec)
            repo_statuses.append(repo_entry)
            continue

        failed_runs = fail_runs_result.get("data") or []
        if not isinstance(failed_runs, list):
            failed_runs = []
        repo_entry["failed_runs_fetched"] = len(failed_runs)

        recent_runs_result = gh_json_runner(
            [
                "run",
                "list",
                "--repo",
                repo,
                "--limit",
                str(recent_run_limit),
                "--json",
                "databaseId,workflowName,headBranch,headSha,createdAt,conclusion,status,event",
            ]
        )
        if not recent_runs_result.get("ok"):
            error_rec = {
                "repo": repo,
                "stage": "run_list_recent",
                "error_code": recent_runs_result.get("error_code", "unknown_error"),
                "message": recent_runs_result.get("message", "failed to fetch recent runs"),
                "stderr": recent_runs_result.get("stderr", ""),
            }
            repo_errors.append(error_rec)
            repo_entry.setdefault("warnings", []).append(error_rec)
            recent_runs = []
        else:
            recent_runs = recent_runs_result.get("data") or []
            if not isinstance(recent_runs, list):
                recent_runs = []
            repo_entry["recent_runs_fetched"] = len(recent_runs)
        recent_runs_by_repo[repo] = recent_runs

        for run in failed_runs:
            run_id = run.get("databaseId")
            if not run_id:
                continue

            run_url = f"https://github.com/{repo}/actions/runs/{run_id}"
            workflow = run.get("workflowName") or "unknown-workflow"
            branch = run.get("headBranch") or ""
            head_sha = run.get("headSha") or ""
            created_at = run.get("createdAt")

            run_view_result = gh_json_runner(
                [
                    "run",
                    "view",
                    str(run_id),
                    "--repo",
                    repo,
                    "--json",
                    "jobs",
                ]
            )
            jobs: list[dict[str, Any]] = []
            if not run_view_result.get("ok"):
                error_rec = {
                    "repo": repo,
                    "stage": "run_view_jobs",
                    "run_id": run_id,
                    "error_code": run_view_result.get("error_code", "unknown_error"),
                    "message": "failed to fetch jobs for failed run",
                    "stderr": run_view_result.get("stderr", ""),
                }
                repo_errors.append(error_rec)
                repo_entry.setdefault("warnings", []).append(error_rec)
            else:
                jobs_raw = (run_view_result.get("data") or {}).get("jobs") or []
                if isinstance(jobs_raw, list):
                    jobs = jobs_raw

            failed_jobs = []
            for job in jobs:
                if (job.get("conclusion") or "").lower() not in {"success", "skipped"}:
                    failed_jobs.append(job)
            if not failed_jobs:
                failed_jobs = [{"name": workflow, "conclusion": run.get("conclusion") or "failure"}]

            for job in failed_jobs:
                job_name = job.get("name") or "unknown-job"
                fallback_sig, fallback_evidence = job_failure_fallback_signature(job, workflow)
                signature = fallback_sig
                evidence_lines = fallback_evidence
                signature_norm = normalize_signature(signature)
                key = (repo, workflow, job_name, signature_norm)
                created_ts = parse_iso(created_at)

                entry = grouped.get(key)
                if entry is None:
                    entry = {
                        "group_key": "|".join([repo, workflow, job_name, signature_norm]),
                        "repo": repo,
                        "workflow": workflow,
                        "job": job_name,
                        "signature": signature,
                        "signature_normalized": signature_norm,
                        "head_branch": branch,
                        "head_sha": head_sha,
                        "first_seen": created_at,
                        "last_seen": created_at,
                        "occurrences": 0,
                        "evidence": evidence_lines[:3],
                        "latest_failure": {
                            "run_id": run_id,
                            "run_url": run_url,
                            "head_sha": head_sha,
                            "head_branch": branch,
                            "event": run.get("event"),
                            "created_at": created_at,
                            "display_title": run.get("displayTitle"),
                        },
                    }
                    grouped[key] = entry

                entry["occurrences"] += 1
                first_seen_ts = parse_iso(entry.get("first_seen"))
                last_seen_ts = parse_iso(entry.get("last_seen"))
                if created_ts and (first_seen_ts is None or created_ts < first_seen_ts):
                    entry["first_seen"] = created_at
                if created_ts and (last_seen_ts is None or created_ts >= last_seen_ts):
                    entry["last_seen"] = created_at
                    entry["latest_failure"] = {
                        "run_id": run_id,
                        "run_url": run_url,
                        "head_sha": head_sha,
                        "head_branch": branch,
                        "event": run.get("event"),
                        "created_at": created_at,
                        "display_title": run.get("displayTitle"),
                    }

        repo_statuses.append(repo_entry)

    groups = list(grouped.values())
    log_cache: dict[tuple[str, int], dict[str, Any]] = {}
    for group in groups:
        latest_failure = group.get("latest_failure") or {}
        run_id = latest_failure.get("run_id")
        if not run_id:
            continue
        cache_key = (group["repo"], str(run_id))
        cached = log_cache.get(cache_key)
        if cached is None:
            cached = gh_text_runner(["run", "view", str(run_id), "--repo", group["repo"], "--log-failed"])
            log_cache[cache_key] = cached
        if cached.get("ok"):
            refined_signature, evidence_lines = extract_signature(cached.get("data") or "", group["signature"])
            group["signature"] = refined_signature
            if evidence_lines:
                group["evidence"] = evidence_lines[:3]
        else:
            error_rec = {
                "repo": group["repo"],
                "stage": "run_log_failed",
                "run_id": run_id,
                "error_code": cached.get("error_code", "unknown_error"),
                "message": "failed to fetch failed job logs",
                "stderr": cached.get("stderr", ""),
            }
            repo_errors.append(error_rec)

    for group in groups:
        group["classification"] = classify_group(group, recent_runs_by_repo.get(group["repo"], []))

    groups.sort(key=lambda item: (parse_iso(item.get("last_seen")) or dt.datetime.min.replace(tzinfo=dt.timezone.utc), item.get("occurrences", 0)), reverse=True)
    active_groups = [g for g in groups if (g.get("classification") or {}).get("status") == "active"]
    stale_groups = [g for g in groups if (g.get("classification") or {}).get("status") == "stale"]
    coverage_error_stages = {"run_list_failures", "run_list_recent", "collector_invocation"}
    coverage_errors = [err for err in repo_errors if (err.get("stage") or "") in coverage_error_stages]

    return {
        "generated_at": utc_now_iso(),
        "repos": repo_statuses,
        "repo_errors": repo_errors,
        "groups": groups,
        "active_groups": active_groups,
        "stale_groups": stale_groups,
        "summary": {
            "repos_total": len(repos),
            "repos_ok": len([r for r in repo_statuses if r.get("status") == "ok"]),
            "repos_error": len([r for r in repo_statuses if r.get("status") == "error"]),
            "coverage_repo_errors": len(coverage_errors),
            "total_groups": len(groups),
            "active_groups": len(active_groups),
            "stale_groups": len(stale_groups),
        },
    }


def load_config(config_path: Path) -> dict[str, Any]:
    raw = json.loads(config_path.read_text(encoding="utf-8"))
    repos = raw.get("canonical_repos")
    if not isinstance(repos, list) or not repos:
        raise ValueError("canonical_repos must be a non-empty array")
    return {
        "canonical_repos": [str(repo) for repo in repos],
        "failed_run_limit": int(raw.get("failed_run_limit", 30)),
        "recent_run_limit": int(raw.get("recent_run_limit", 80)),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Collect and classify cross-repo GitHub Actions failures.")
    default_config = Path(__file__).resolve().parents[2] / "configs" / "github-actions-failure-audit.json"
    parser.add_argument("--config", default=str(default_config), help="Path to repo config JSON.")
    parser.add_argument("--failed-run-limit", type=int, default=None, help="Override failed run fetch limit per repo.")
    parser.add_argument("--recent-run-limit", type=int, default=None, help="Override recent run fetch limit per repo.")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON report (default behavior).")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config = load_config(Path(args.config))
    failed_limit = args.failed_run_limit if args.failed_run_limit is not None else config["failed_run_limit"]
    recent_limit = args.recent_run_limit if args.recent_run_limit is not None else config["recent_run_limit"]
    report = build_report(
        repos=config["canonical_repos"],
        failed_run_limit=failed_limit,
        recent_run_limit=recent_limit,
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
