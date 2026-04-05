#!/usr/bin/env python3
"""Create a fresh golden CSV fixture run directory.

Creates a unique run-id, a run directory, and writes run.json with
the graph shape from the saved template. Does NOT touch Beads.

Usage:
    python3 create_run.py [--run-id ID] [--template-dir DIR]

Prints the run-id to stdout on success.
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


RUN_ROOT = "/tmp/dx-loop-fixtures/golden-csv"

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_TEMPLATE_DIR = SCRIPT_DIR.parent / "template"


def generate_run_id() -> str:
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"golden-csv-{ts}"


def create_run(
    run_id: Optional[str] = None, template_dir: Optional[Path] = None
) -> str:
    if run_id is None:
        run_id = generate_run_id()
    if template_dir is None:
        template_dir = REPO_TEMPLATE_DIR

    spec_path = template_dir / "run_spec.json"
    if not spec_path.exists():
        print(f"ERROR: run_spec.json not found at {spec_path}", file=sys.stderr)
        sys.exit(1)

    run_dir = Path(RUN_ROOT) / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    output_csv = run_dir / "output.csv"
    if not output_csv.exists():
        output_csv.touch()

    run_meta = {
        "run_id": run_id,
        "run_dir": str(run_dir),
        "output_csv": str(output_csv),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "status": "created",
        "spec": json.loads(spec_path.read_text()),
    }

    (run_dir / "run.json").write_text(json.dumps(run_meta, indent=2) + "\n")
    return run_id


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a golden CSV fixture run")
    parser.add_argument(
        "--run-id", default=None, help="Explicit run-id (auto-generated if omitted)"
    )
    parser.add_argument(
        "--template-dir", default=None, help="Path to template directory"
    )
    args = parser.parse_args()

    tdir = Path(args.template_dir) if args.template_dir else None
    rid = create_run(run_id=args.run_id, template_dir=tdir)
    print(rid)


if __name__ == "__main__":
    main()
