#!/usr/bin/env python3
"""Run progressive OpenCode benchmark phases with explicit gate outputs.

V8.x Reliability Hardening:
- Model preflight before wave launch
- Model selection with fallback
- Taxonomy codes for failure classification
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import subprocess
from typing import Any

from governance_gates import baseline_gate, integrity_gate
from opencode_preflight import run_preflight


TAXONOMY_CODES = {
    "model_unavailable": "model_unavailable",
    "preflight_failed": "preflight_failed",
    "stalled_run": "stalled_run",
    "ancestry_gate_failed": "ancestry_gate_failed",
    "scope_drift_failed": "scope_drift_failed",
    "baseline_gate_failed": "baseline_gate_failed",
    "integrity_gate_failed": "integrity_gate_failed",
}


PHASES: dict[str, dict[str, Any]] = {
    "phase1_smoke": {
        "description": "OpenCode headless smoke on one coding prompt.",
        "workflows": ["opencode_run_headless"],
        "prompt_ids": ["coding_ability_2"],
        "parallel": 1,
        "max_retries": 1,
        "timeout_sec": 300,
        "min_success_rate": 1.0,
    },
    "phase2_6stream": {
        "description": "OpenCode 6-stream throughput wave (3 prompts x 2 rounds equivalent).",
        "workflows": ["opencode_run_headless"],
        "prompt_ids": [
            "coding_ability_2",
            "latency_speed_1",
            "robustness_partial_context_1",
        ],
        "parallel": 6,
        "max_retries": 1,
        "timeout_sec": 300,
        "min_success_rate": 1.0,
    },
    "phase3_real_coding_gate": {
        "description": "OpenCode real coding certification gate for deferred DX fixes.",
        "workflows": ["opencode_run_headless", "opencode_server_http"],
        "prompt_ids": [
            "coding_ability_1",
            "coding_ability_2",
            "latency_speed_1",
            "robustness_partial_context_1",
        ],
        "parallel": 6,
        "max_retries": 1,
        "timeout_sec": 420,
        "min_success_rate": 0.9,
    },
}


def utc_now_compact() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def run_cmd(cmd: list[str], cwd: pathlib.Path) -> str:
    proc = subprocess.run(cmd, cwd=str(cwd), check=True, capture_output=True, text=True)
    return proc.stdout.strip()


def load_prompts(path: pathlib.Path) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return list(payload.get("prompts", []))


def write_filtered_prompts(
    source_prompts: pathlib.Path,
    selected_ids: list[str],
    out_path: pathlib.Path,
) -> None:
    prompts = load_prompts(source_prompts)
    selected = [p for p in prompts if p.get("id") in set(selected_ids)]
    payload = {"version": 1, "name": "progressive-opencode-phase", "prompts": selected}
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def parse_success_rate(summary_json_path: pathlib.Path) -> float:
    payload = json.loads(summary_json_path.read_text(encoding="utf-8"))
    for row in payload.get("system_metrics", []):
        if row.get("system") == "opencode":
            return float(row.get("success_rate") or 0.0)
    return 0.0


def phase_order_index(phase_name: str) -> int:
    names = list(PHASES.keys())
    return names.index(phase_name)


def previous_phase_name(phase_name: str) -> str | None:
    idx = phase_order_index(phase_name)
    if idx == 0:
        return None
    return list(PHASES.keys())[idx - 1]


def gate_state_path(output_dir: pathlib.Path) -> pathlib.Path:
    return output_dir / "progressive" / "state.json"


def load_gate_state(path: pathlib.Path) -> dict[str, Any]:
    if not path.exists():
        return {"last_passed_phase": None, "history": []}
    return json.loads(path.read_text(encoding="utf-8"))


def save_gate_state(path: pathlib.Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Progressive OpenCode benchmark waves")
    parser.add_argument("--phase", required=True, choices=list(PHASES.keys()))
    parser.add_argument(
        "--model",
        default="zai-coding-plan/glm-5",
        help="OpenCode model in provider/model format",
    )
    parser.add_argument(
        "--prompts-file",
        type=pathlib.Path,
        default=pathlib.Path(
            "scripts/benchmarks/opencode_cc_glm/benchmark_prompts.json"
        ),
    )
    parser.add_argument(
        "--output-dir",
        type=pathlib.Path,
        default=pathlib.Path("artifacts/opencode-cc-glm-bench"),
    )
    parser.add_argument("--cwd", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument(
        "--required-baseline",
        default="",
        help="Optional required commit baseline for pre-dispatch runtime gate",
    )
    parser.add_argument(
        "--reported-commit",
        default="",
        help="Optional reported commit SHA for post-wave integrity gate",
    )
    parser.add_argument(
        "--branch",
        default="",
        help="Branch for integrity gate (defaults to current branch in --cwd repo)",
    )
    parser.add_argument(
        "--force", action="store_true", help="Skip previous-phase pass check"
    )
    parser.add_argument(
        "--skip-preflight", action="store_true", help="Skip model preflight check"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    phase_cfg = PHASES[args.phase]
    output_dir = args.output_dir.resolve()
    repo_root = pathlib.Path.cwd().resolve()
    scripts_dir = repo_root / "scripts" / "benchmarks" / "opencode_cc_glm"
    launch = scripts_dir / "launch_parallel_jobs.py"
    collect = scripts_dir / "collect_results.py"
    summarize = scripts_dir / "summarize_results.py"

    state_file = gate_state_path(output_dir)
    state = load_gate_state(state_file)
    prev = previous_phase_name(args.phase)
    if not args.force and prev is not None and state.get("last_passed_phase") != prev:
        raise SystemExit(
            f"Gate blocked: previous phase '{prev}' not passed. "
            f"Current state last_passed_phase={state.get('last_passed_phase')!r}"
        )

    run_id = f"progressive-{args.phase}-{utc_now_compact()}"
    filtered_prompts = output_dir / run_id / "phase_prompts.json"
    filtered_prompts.parent.mkdir(parents=True, exist_ok=True)
    write_filtered_prompts(
        args.prompts_file.resolve(), phase_cfg["prompt_ids"], filtered_prompts
    )

    preflight_result: dict[str, Any] | None = None
    if not args.skip_preflight:
        preflight = run_preflight(preferred_model=args.model, json_output=False)
        preflight_result = preflight.to_dict()
        if not preflight.passed:
            record = {
                "phase": args.phase,
                "run_id": run_id,
                "run_dir": str(filtered_prompts.parent),
                "model": args.model,
                "model_selected": None,
                "workflows": phase_cfg["workflows"],
                "prompt_ids": phase_cfg["prompt_ids"],
                "success_rate": 0.0,
                "min_success_rate": phase_cfg["min_success_rate"],
                "passed": False,
                "reason_code": preflight.reason_code,
                "taxonomy": TAXONOMY_CODES.get(
                    preflight.reason_code, preflight.reason_code
                ),
                "preflight": preflight_result,
                "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            }
            state.setdefault("history", []).append(record)
            save_gate_state(state_file, state)
            print(json.dumps(record, indent=2))
            return 1

    effective_model = (
        preflight_result.get("selected_model") if preflight_result else args.model
    ) or args.model

    baseline_result: dict[str, Any] | None = None
    if args.required_baseline:
        baseline_eval = baseline_gate(args.cwd.resolve(), args.required_baseline)
        baseline_result = baseline_eval.to_dict()
        if not baseline_eval.passed:
            record = {
                "phase": args.phase,
                "run_id": run_id,
                "run_dir": "",
                "model": args.model,
                "model_selected": effective_model,
                "workflows": phase_cfg["workflows"],
                "prompt_ids": phase_cfg["prompt_ids"],
                "success_rate": 0.0,
                "min_success_rate": phase_cfg["min_success_rate"],
                "passed": False,
                "reason_code": TAXONOMY_CODES["baseline_gate_failed"],
                "preflight": preflight_result,
                "baseline_gate": baseline_result,
                "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            }
            state.setdefault("history", []).append(record)
            save_gate_state(state_file, state)
            print(json.dumps(record, indent=2))
            return 4

    workflows_csv = ",".join(phase_cfg["workflows"])
    run_cmd(
        [
            str(launch),
            "--prompts-file",
            str(filtered_prompts),
            "--run-id",
            run_id,
            "--workflows",
            workflows_csv,
            "--parallel",
            str(phase_cfg["parallel"]),
            "--model",
            effective_model,
            "--output-dir",
            str(output_dir),
            "--max-retries",
            str(phase_cfg["max_retries"]),
            "--timeout-sec",
            str(phase_cfg["timeout_sec"]),
            "--cwd",
            str(args.cwd.resolve()),
        ],
        cwd=repo_root,
    )

    run_dir = output_dir / run_id
    results_json = run_dir / "collected" / "results.json"
    summary_json = run_dir / "collected" / "summary.json"

    run_cmd(
        [
            str(collect),
            "--run-dir",
            str(run_dir),
            "--out-json",
            str(results_json),
        ],
        cwd=repo_root,
    )
    run_cmd(
        [
            str(summarize),
            "--results-json",
            str(results_json),
            "--out-json",
            str(summary_json),
        ],
        cwd=repo_root,
    )

    success_rate = parse_success_rate(summary_json)
    passed = success_rate >= float(phase_cfg["min_success_rate"])
    integrity_result: dict[str, Any] | None = None
    if args.reported_commit:
        integ_eval = integrity_gate(
            args.cwd.resolve(), args.reported_commit, args.branch or None
        )
        integrity_result = integ_eval.to_dict()
        passed = passed and bool(integ_eval.passed)

    record = {
        "phase": args.phase,
        "run_id": run_id,
        "run_dir": str(run_dir),
        "model": args.model,
        "model_selected": effective_model,
        "fallback_reason": preflight_result.get("fallback_reason")
        if preflight_result
        else None,
        "workflows": phase_cfg["workflows"],
        "prompt_ids": phase_cfg["prompt_ids"],
        "success_rate": success_rate,
        "min_success_rate": phase_cfg["min_success_rate"],
        "passed": passed,
        "preflight": preflight_result,
        "baseline_gate": baseline_result,
        "integrity_gate": integrity_result,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }

    state.setdefault("history", []).append(record)
    if passed:
        state["last_passed_phase"] = args.phase
    save_gate_state(state_file, state)

    print(json.dumps(record, indent=2))
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
