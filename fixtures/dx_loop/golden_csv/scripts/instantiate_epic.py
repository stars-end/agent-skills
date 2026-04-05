#!/usr/bin/env python3
"""Create a fresh Beads epic from the golden CSV fixture template.

Uses `bd` CLI to create an epic with the canonical child shape.
Supports --dry-run to print the plan without touching Beads.

Usage:
    python3 instantiate_epic.py [--dry-run]

Prints the new epic id (or dry-run plan) to stdout.
Requires: bd CLI in PATH, active Beads Dolt session.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_TEMPLATE_DIR = SCRIPT_DIR.parent / "template"

EPIC_TITLE = "Golden dx-loop CSV requalification run"

TASKS = [
    {"index": 1, "title": "Append line 1", "deps": []},
    {"index": 2, "title": "Append line 2", "deps": [1]},
    {"index": 3, "title": "Append line 3", "deps": [2]},
    {"index": 4, "title": "Append line 4", "deps": [2]},
    {"index": 5, "title": "Append line 5", "deps": [3, 4]},
]


def bd(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bd"] + list(args),
        capture_output=True,
        text=True,
        timeout=30,
    )


def instantiate_epic(dry_run: bool = False) -> str:
    if dry_run:
        plan = {
            "action": "instantiate_epic",
            "dry_run": True,
            "epic_title": EPIC_TITLE,
            "children": TASKS,
            "commands": [],
        }

        cmds = [f'bd create --title "{EPIC_TITLE}" --type epic']
        cmds.append("# After epic is created, replace <EPIC_ID> below:")
        for t in TASKS:
            dep_str = ""
            if t["deps"]:
                dep_parts = [f"<EPIC_ID>.{d}" for d in t["deps"]]
                dep_str = " --deps " + ",".join(dep_parts)
            cmds.append(
                f'bd create --title "{t["title"]}" --type task --parent <EPIC_ID>{dep_str}'
            )

        plan["commands"] = cmds
        print(json.dumps(plan, indent=2))
        return "dry-run"

    r = bd("create", "--title", EPIC_TITLE, "--type", "epic")
    if r.returncode != 0:
        print(f"ERROR: bd create epic failed: {r.stderr.strip()}", file=sys.stderr)
        sys.exit(1)

    epic_id = r.stdout.strip().split("\n")[-1].strip()
    if not epic_id:
        print(
            f"ERROR: could not parse epic id from: {r.stdout.strip()}", file=sys.stderr
        )
        sys.exit(1)

    print(f"Created epic: {epic_id}", file=sys.stderr)

    child_ids = {}
    for t in TASKS:
        cmd = [
            "bd",
            "create",
            "--title",
            t["title"],
            "--type",
            "task",
            "--parent",
            epic_id,
        ]
        for dep_idx in t["deps"]:
            dep_id = child_ids.get(dep_idx)
            if dep_id:
                cmd += ["--deps", dep_id]

        cr = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if cr.returncode != 0:
            print(
                f"ERROR: bd create task {t['index']} failed: {cr.stderr.strip()}",
                file=sys.stderr,
            )
            sys.exit(1)

        child_id = cr.stdout.strip().split("\n")[-1].strip()
        child_ids[t["index"]] = child_id
        print(f"Created task {t['index']}: {child_id} ({t['title']})", file=sys.stderr)

    return epic_id


def main() -> None:
    parser = argparse.ArgumentParser(description="Instantiate a golden CSV Beads epic")
    parser.add_argument(
        "--dry-run", action="store_true", help="Print plan without creating"
    )
    args = parser.parse_args()

    result = instantiate_epic(dry_run=args.dry_run)
    if not args.dry_run:
        print(result)


if __name__ == "__main__":
    main()
