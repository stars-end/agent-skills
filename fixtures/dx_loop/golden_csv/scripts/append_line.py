#!/usr/bin/env python3
"""Append one deterministic line to the current run CSV.

Usage:
    python3 append_line.py --run-dir DIR --task-index N

Looks up the line content from run_spec.json, appends it to output.csv,
and updates run.json with the append event.
"""

import argparse
import json
import sys
from pathlib import Path


def append_line(run_dir: str, task_index: int) -> None:
    rdir = Path(run_dir)
    run_json = rdir / "run.json"
    output_csv = rdir / "output.csv"

    if not run_json.exists():
        print(f"ERROR: run.json not found in {rdir}", file=sys.stderr)
        sys.exit(1)

    run_meta = json.loads(run_json.read_text())
    spec = run_meta["spec"]

    task = None
    for t in spec["tasks"]:
        if t["index"] == task_index:
            task = t
            break

    if task is None:
        print(f"ERROR: no task with index {task_index} in spec", file=sys.stderr)
        sys.exit(1)

    line = task["line"]

    with output_csv.open("a") as f:
        f.write(line + "\n")

    append_log = run_meta.get("append_log", [])
    append_log.append(
        {
            "task_index": task_index,
            "line": line,
            "title": task["title"],
        }
    )
    run_meta["append_log"] = append_log
    run_meta["status"] = "in-progress"

    run_json.write_text(json.dumps(run_meta, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Append a line to the golden CSV run")
    parser.add_argument("--run-dir", required=True, help="Path to the run directory")
    parser.add_argument(
        "--task-index", required=True, type=int, help="Task index (1-5)"
    )
    args = parser.parse_args()

    append_line(args.run_dir, args.task_index)


if __name__ == "__main__":
    main()
