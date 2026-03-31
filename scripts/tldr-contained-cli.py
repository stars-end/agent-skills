#!/usr/bin/env python3
"""Contained CLI entrypoint for llm-tldr."""

from __future__ import annotations

import sys

from tldr_contained_runtime import run_cli


if __name__ == "__main__":
    raise SystemExit(run_cli(sys.argv[1:]))
