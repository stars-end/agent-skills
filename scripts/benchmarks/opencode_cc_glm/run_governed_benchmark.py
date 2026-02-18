#!/usr/bin/env python3
"""Provider-agnostic governed benchmark runner.

This wrapper executes any supported workflows through a shared governance layer:
1) optional pre-dispatch baseline gate
2) benchmark execution (via launch_parallel_jobs.py)
3) collection + summary generation
4) optional post-wave integrity gate
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import subprocess
from typing import Any

from governance_gates import baseline_gate, integrity_gate


def utc_now_compact() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def run_cmd(cmd: list[str], cwd: pathlib.Path) -> str:
    proc = subprocess.run(cmd, cwd=str(cwd), check=True, capture_output=True, text=True)
    return proc.stdout.strip()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run governed benchmark wave")
    parser.add_argument("--run-id", default="")
    parser.add_argument("--workflows", required=True, help="Comma-separated workflow IDs")
    parser.add_argument(
        "--prompts-file",
        type=pathlib.Path,
        default=pathlib.Path("scripts/benchmarks/opencode_cc_glm/benchmark_prompts.json"),
    )
    parser.add_argument("--model", default="glm-5")
    parser.add_argument("--parallel", type=int, default=6)
    parser.add_argument("--max-retries", type=int, default=1)
    parser.add_argument("--timeout-sec", type=float, default=300.0)
    parser.add_argument(
        "--output-dir",
        type=pathlib.Path,
        default=pathlib.Path("artifacts/opencode-cc-glm-bench"),
    )
    parser.add_argument("--cwd", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--required-baseline", default="")
    parser.add_argument("--reported-commit", default="")
    parser.add_argument("--branch", default="")
    return parser.parse_args()


def load_results(results_json: pathlib.Path) -> dict[str, Any]:
    return json.loads(results_json.read_text(encoding="utf-8"))


def compute_run_success(results_payload: dict[str, Any]) -> bool:
    for row in results_payload.get("aggregates", {}).get("by_workflow", []):
        if float(row.get("success_rate") or 0.0) < 1.0:
            return False
    return True


def main() -> int:
    args = parse_args()
    repo_root = pathlib.Path.cwd().resolve()
    scripts_dir = repo_root / "scripts" / "benchmarks" / "opencode_cc_glm"
    launch = scripts_dir / "launch_parallel_jobs.py"
    collect = scripts_dir / "collect_results.py"
    summarize = scripts_dir / "summarize_results.py"

    run_id = args.run_id or f"governed-{utc_now_compact()}"
    output_dir = args.output_dir.resolve()
    run_dir = output_dir / run_id

    baseline_result: dict[str, Any] | None = None
    if args.required_baseline:
        b = baseline_gate(args.cwd.resolve(), args.required_baseline)
        baseline_result = b.to_dict()
        if not b.passed:
            payload = {
                "run_id": run_id,
                "passed": False,
                "reason_code": "baseline_gate_failed",
                "baseline_gate": baseline_result,
                "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            }
            run_dir.mkdir(parents=True, exist_ok=True)
            (run_dir / "governance_report.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
            print(json.dumps(payload, indent=2))
            return 4

    run_cmd(
        [
            str(launch),
            "--prompts-file",
            str(args.prompts_file.resolve()),
            "--run-id",
            run_id,
            "--workflows",
            args.workflows,
            "--parallel",
            str(args.parallel),
            "--model",
            args.model,
            "--output-dir",
            str(output_dir),
            "--max-retries",
            str(args.max_retries),
            "--timeout-sec",
            str(args.timeout_sec),
            "--cwd",
            str(args.cwd.resolve()),
        ],
        cwd=repo_root,
    )

    results_json = run_dir / "collected" / "results.json"
    summary_json = run_dir / "collected" / "summary.json"
    run_cmd([str(collect), "--run-dir", str(run_dir), "--out-json", str(results_json)], cwd=repo_root)
    run_cmd([str(summarize), "--results-json", str(results_json), "--out-json", str(summary_json)], cwd=repo_root)

    integrity_result: dict[str, Any] | None = None
    if args.reported_commit:
        integ = integrity_gate(args.cwd.resolve(), args.reported_commit, args.branch or None)
        integrity_result = integ.to_dict()

    results_payload = load_results(results_json)
    run_success = compute_run_success(results_payload)
    passed = run_success and (integrity_result is None or bool(integrity_result.get("passed")))

    report = {
        "run_id": run_id,
        "run_dir": str(run_dir),
        "workflows": [w.strip() for w in args.workflows.split(",") if w.strip()],
        "model": args.model,
        "passed": passed,
        "run_success": run_success,
        "baseline_gate": baseline_result,
        "integrity_gate": integrity_result,
        "summary_json": str(summary_json),
        "summary_md": str(run_dir / "collected" / "summary.md"),
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    (run_dir / "governance_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if passed else 3


if __name__ == "__main__":
    raise SystemExit(main())
