#!/usr/bin/env python3
"""CLI wrapper for cross-repo GitHub Actions failure grouping."""

from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    lib_dir = script_dir / "lib"
    if str(lib_dir) not in sys.path:
        sys.path.insert(0, str(lib_dir))
    from github_actions_audit import main as audit_main

    return audit_main()


if __name__ == "__main__":
    raise SystemExit(main())
