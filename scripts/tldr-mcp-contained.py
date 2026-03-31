#!/usr/bin/env python3
"""Contained MCP server entrypoint for llm-tldr."""

from __future__ import annotations

from tldr_contained_runtime import run_mcp


if __name__ == "__main__":
    raise SystemExit(run_mcp())
