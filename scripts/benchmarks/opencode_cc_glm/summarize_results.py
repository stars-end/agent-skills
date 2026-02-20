#!/usr/bin/env python3
"""Render benchmark summary tables (Markdown + JSON)."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
from typing import Any



def utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")



def fmt_ms(value: Any) -> str:
    if value is None:
        return "-"
    return f"{int(round(float(value)))}"



def fmt_rate(value: Any) -> str:
    if value is None:
        return "-"
    return f"{float(value) * 100:.1f}%"



def markdown_table(headers: list[str], rows: list[list[str]]) -> str:
    head = "| " + " | ".join(headers) + " |"
    sep = "| " + " | ".join(["---"] * len(headers)) + " |"
    body = ["| " + " | ".join(row) + " |" for row in rows]
    return "\n".join([head, sep, *body])



def workflow_rows(data: dict[str, Any]) -> list[list[str]]:
    rows = []
    for row in data["aggregates"]["by_workflow"]:
        rows.append(
            [
                str(row["workflow_id"]),
                str(row["job_count"]),
                fmt_rate(row["success_rate"]),
                fmt_rate(row["retry_rate"]),
                fmt_ms(row["startup_latency_ms_mean"]),
                fmt_ms(row["first_output_latency_ms_p50"]),
                fmt_ms(row["completion_latency_ms_p50"]),
            ]
        )
    return rows



def system_rows(data: dict[str, Any]) -> list[list[str]]:
    rows = []
    for row in data["aggregates"]["by_system"]:
        rows.append(
            [
                str(row["system"]),
                str(row["job_count"]),
                fmt_rate(row["success_rate"]),
                fmt_rate(row["retry_rate"]),
                fmt_ms(row["first_output_latency_ms_p50"]),
                fmt_ms(row["completion_latency_ms_p50"]),
            ]
        )
    return rows



def prompt_side_by_side_rows(data: dict[str, Any]) -> tuple[list[str], list[list[str]]]:
    matrix = data["aggregates"]["prompt_matrix"]
    workflows = sorted({workflow for row in matrix for workflow in row["workflows"].keys()})
    headers = ["prompt_id", "category", *workflows]

    rows = []
    for row in matrix:
        cells = [row["prompt_id"], row.get("prompt_category") or "-"]
        for workflow in workflows:
            item = row["workflows"].get(workflow)
            if not item:
                cells.append("-")
                continue
            if item["success"]:
                cells.append(f"ok ({fmt_ms(item['completion_latency_ms'])}ms)")
            else:
                category = item.get("failure_category") or "unknown"
                cells.append(f"fail:{category}")
        rows.append(cells)

    return headers, rows



def failure_taxonomy_rows(data: dict[str, Any]) -> list[list[str]]:
    category_counts = data["aggregates"]["failure_taxonomy"]["category_counts"]
    reason_counts = data["aggregates"]["failure_taxonomy"]["reason_counts"]

    rows: list[list[str]] = []
    for category in sorted(category_counts):
        rows.append([category, str(category_counts[category]), "category"])
    for reason in sorted(reason_counts):
        rows.append([reason, str(reason_counts[reason]), "reason"])

    if not rows:
        rows.append(["none", "0", "category"])
    return rows



def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Summarize benchmark results")
    parser.add_argument("--results-json", required=True, type=pathlib.Path)
    parser.add_argument("--out-md", type=pathlib.Path, default=None)
    parser.add_argument("--out-json", type=pathlib.Path, default=None)
    return parser.parse_args()



def main() -> int:
    args = parse_args()
    results_path = args.results_json.resolve()
    data = json.loads(results_path.read_text(encoding="utf-8"))

    out_dir = results_path.parent
    out_md = args.out_md.resolve() if args.out_md else out_dir / "summary.md"
    out_json = args.out_json.resolve() if args.out_json else out_dir / "summary.json"

    workflow_table = markdown_table(
        [
            "workflow_id",
            "jobs",
            "success_rate",
            "retry_rate",
            "startup_ms_mean",
            "first_output_ms_p50",
            "completion_ms_p50",
        ],
        workflow_rows(data),
    )
    system_table = markdown_table(
        ["system", "jobs", "success_rate", "retry_rate", "first_output_ms_p50", "completion_ms_p50"],
        system_rows(data),
    )
    side_headers, side_rows = prompt_side_by_side_rows(data)
    side_table = markdown_table(side_headers, side_rows)
    failure_table = markdown_table(["key", "count", "kind"], failure_taxonomy_rows(data))

    markdown = "\n".join(
        [
            f"# Benchmark Summary: {data['run_id']}",
            "",
            f"Generated: {utc_now_iso()}",
            f"Total records: {data['record_count']}",
            "",
            "## Workflow Metrics",
            workflow_table,
            "",
            "## System Comparison",
            system_table,
            "",
            "## Prompt Side-by-Side",
            side_table,
            "",
            "## Failure Taxonomy",
            failure_table,
            "",
        ]
    )

    out_md.write_text(markdown, encoding="utf-8")

    summary_payload = {
        "run_id": data["run_id"],
        "generated_at": utc_now_iso(),
        "record_count": data["record_count"],
        "workflow_metrics": data["aggregates"]["by_workflow"],
        "system_metrics": data["aggregates"]["by_system"],
        "failure_taxonomy": data["aggregates"]["failure_taxonomy"],
    }
    out_json.write_text(json.dumps(summary_payload, indent=2), encoding="utf-8")

    print(json.dumps({"run_id": data["run_id"], "summary_md": str(out_md), "summary_json": str(out_json)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
