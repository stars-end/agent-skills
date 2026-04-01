#!/usr/bin/env python3
"""Contained daemon launcher for llm-tldr."""

from __future__ import annotations

import sys

from tldr_contained_runtime import run_daemon


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: tldr-contained-daemon.py <project-path>")
    raise SystemExit(run_daemon(sys.argv[1]))
