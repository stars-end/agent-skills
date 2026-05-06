#!/usr/bin/env python3
"""Create a goal-seeking eval loop artifact directory."""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Initialize eval loop artifacts")
    parser.add_argument("artifact_root")
    parser.add_argument("--goal", default="")
    parser.add_argument("--feature-key", default="")
    parser.add_argument("--max-cycles", type=int, default=10)
    parser.add_argument("--max-subagents", type=int, default=2)
    parser.add_argument("--model", default="gpt-5.3-codex")
    parser.add_argument("--reasoning-effort", default="medium")
    args = parser.parse_args()

    root = Path(args.artifact_root)
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
        "max_cycles": args.max_cycles,
        "max_subagents": args.max_subagents,
        "default_model": args.model,
        "default_reasoning_effort": args.reasoning_effort,
        "artifact_root": os.fspath(root),
    }
    (root / "run.json").write_text(json.dumps(run, indent=2, sort_keys=True) + "\n")
    (root / "baseline" / "command.txt").touch(exist_ok=True)
    print(root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
