#!/usr/bin/env python3
"""Collect raw benchmark records into a normalized machine-readable bundle."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
from collections import Counter, defaultdict
from typing import Any



def utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")



def percentile(values: list[float], pct: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    index = (len(ordered) - 1) * pct
    lower = int(index)
    upper = min(lower + 1, len(ordered) - 1)
    fraction = index - lower
    return ordered[lower] * (1 - fraction) + ordered[upper] * fraction



def safe_mean(values: list[float]) -> float | None:
    if not values:
        return None
    return sum(values) / len(values)



def summarize_group(records: list[dict[str, Any]], group_key: str) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        grouped[str(record[group_key])].append(record)

    summary_rows: list[dict[str, Any]] = []
    for key, items in sorted(grouped.items(), key=lambda kv: kv[0]):
        startup = [float(r["startup_latency_ms"]) for r in items if r.get("startup_latency_ms") is not None]
        first_output = [
            float(r["first_output_latency_ms"])
            for r in items
            if r.get("first_output_latency_ms") is not None
        ]
        completion = [
            float(r["completion_latency_ms"]) for r in items if r.get("completion_latency_ms") is not None
        ]
        success_count = sum(1 for r in items if r.get("success"))
        retries = sum(int(r.get("retry_count") or 0) for r in items)

        summary_rows.append(
            {
                group_key: key,
                "job_count": len(items),
                "success_count": success_count,
                "success_rate": success_count / len(items) if items else 0.0,
                "retry_count": retries,
                "retry_rate": retries / len(items) if items else 0.0,
                "startup_latency_ms_mean": safe_mean(startup),
                "first_output_latency_ms_p50": percentile(first_output, 0.50),
                "first_output_latency_ms_p95": percentile(first_output, 0.95),
                "completion_latency_ms_p50": percentile(completion, 0.50),
                "completion_latency_ms_p95": percentile(completion, 0.95),
            }
        )
    return summary_rows



def build_prompt_matrix(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    matrix: dict[str, dict[str, Any]] = {}
    workflows = sorted({record["workflow_id"] for record in records})

    for record in records:
        prompt_id = record["prompt_id"]
        row = matrix.setdefault(
            prompt_id,
            {
                "prompt_id": prompt_id,
                "prompt_category": record.get("prompt_category"),
                "workflows": {workflow: None for workflow in workflows},
            },
        )
        row["workflows"][record["workflow_id"]] = {
            "success": bool(record.get("success")),
            "completion_latency_ms": record.get("completion_latency_ms"),
            "retry_count": record.get("retry_count"),
            "failure_category": record.get("failure_category"),
            "failure_reason": record.get("failure_reason"),
        }

    return [matrix[prompt_id] for prompt_id in sorted(matrix)]



def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Collect benchmark records")
    parser.add_argument("--run-dir", required=True, type=pathlib.Path)
    parser.add_argument("--out-json", type=pathlib.Path, default=None)
    parser.add_argument("--out-ndjson", type=pathlib.Path, default=None)
    return parser.parse_args()



def main() -> int:
    args = parse_args()
    run_dir = args.run_dir.resolve()
    raw_dir = run_dir / "raw"
    if not raw_dir.exists():
        raise SystemExit(f"raw dir not found: {raw_dir}")

    record_paths = sorted(
        path
        for path in raw_dir.glob("*.json")
        if "__" in path.name and not path.name.endswith("manifest.json")
    )
    records = [json.loads(path.read_text(encoding="utf-8")) for path in record_paths]

    failure_counts = Counter(
        record["failure_category"]
        for record in records
        if record.get("failure_category")
    )
    failure_reason_counts = Counter(
        record["failure_reason"]
        for record in records
        if record.get("failure_reason")
    )

    workflow_summary = summarize_group(records, "workflow_id")
    system_summary = summarize_group(records, "system")

    payload = {
        "run_id": json.loads((run_dir / "manifest.json").read_text(encoding="utf-8"))["run_id"],
        "generated_at": utc_now_iso(),
        "run_dir": str(run_dir),
        "record_count": len(records),
        "records": records,
        "aggregates": {
            "by_workflow": workflow_summary,
            "by_system": system_summary,
            "failure_taxonomy": {
                "category_counts": dict(failure_counts),
                "reason_counts": dict(failure_reason_counts),
            },
            "prompt_matrix": build_prompt_matrix(records),
        },
    }

    out_dir = run_dir / "collected"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_json = args.out_json.resolve() if args.out_json else out_dir / "results.json"
    out_ndjson = args.out_ndjson.resolve() if args.out_ndjson else out_dir / "records.ndjson"

    out_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    with out_ndjson.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record))
            handle.write("\n")

    print(json.dumps({"run_id": payload["run_id"], "records": len(records), "results_json": str(out_json)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
