#!/usr/bin/env python3
"""Create a goal-seeking eval loop artifact directory."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def infer_git_sha(worktree: str) -> str:
    if not worktree:
        return ""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=worktree,
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return ""
    return result.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description="Initialize eval loop artifacts")
    parser.add_argument("artifact_root")
    parser.add_argument("--goal", default="")
    parser.add_argument("--feature-key", default="")
    parser.add_argument("--eval-set-version", default="")
    parser.add_argument("--score-rubric-version", default="")
    parser.add_argument("--worktree", default="")
    parser.add_argument("--git-sha", default="")
    parser.add_argument("--max-cycles", type=int, default=10)
    parser.add_argument("--max-subagents", type=int, default=3)
    parser.add_argument("--model", default="gpt-5.3-codex")
    parser.add_argument("--reasoning-effort", default="medium")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    root = Path(args.artifact_root)
    if root.exists() and not root.is_dir():
        print(f"ERROR: artifact root exists but is not a directory: {root}", file=sys.stderr)
        return 2
    if root.exists() and any(root.iterdir()) and not args.force:
        print(
            f"ERROR: artifact root is not empty: {root} (use --force to reuse it)",
            file=sys.stderr,
        )
        return 2

    for path in [
        root,
        root / "baseline" / "logs",
        root / "cycles",
        root / "final",
    ]:
        path.mkdir(parents=True, exist_ok=True)

    run = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "goal": args.goal,
        "feature_key": args.feature_key,
        "eval_set_version": args.eval_set_version,
        "score_rubric_version": args.score_rubric_version,
        "max_cycles": args.max_cycles,
        "max_subagents": args.max_subagents,
        "default_model": args.model,
        "default_reasoning_effort": args.reasoning_effort,
        "artifact_root": os.fspath(root),
        "worktree": args.worktree,
        "git_sha": args.git_sha or infer_git_sha(args.worktree),
    }
    (root / "run.json").write_text(json.dumps(run, indent=2, sort_keys=True) + "\n")
    (root / "baseline" / "command.txt").touch(exist_ok=True)
    print(root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
