#!/usr/bin/env python3
"""Daemon-backed llm-tldr fallback helper for MCP hydration gaps.

This helper intentionally uses tldr.mcp_server tool functions so calls flow
through `_send_command(...)` and daemon socket transport, matching the MCP
fast path instead of plain CLI direct API calls.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from tldr_contained_runtime import apply_containment_patches


def _json_or_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    try:
        return json.dumps(value, indent=2, sort_keys=True)
    except TypeError:
        return str(value)


def _resolve_project(project: str) -> str:
    return str(Path(project).expanduser().resolve())


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="tldr-daemon-fallback",
        description=(
            "Contained llm-tldr fallback helper using daemon-backed MCP command "
            "path (socket transport)."
        ),
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    context_cmd = subparsers.add_parser("context", help="Run daemon-backed context query")
    context_cmd.add_argument("--repo", "--project", dest="project", required=True)
    context_cmd.add_argument("--entry", required=True)
    context_cmd.add_argument("--depth", type=int, default=2)
    context_cmd.add_argument("--language", default="python")

    semantic_cmd = subparsers.add_parser("semantic", help="Run daemon-backed semantic query")
    semantic_cmd.add_argument("--repo", "--project", dest="project", required=True)
    semantic_cmd.add_argument("--query", required=True)
    semantic_cmd.add_argument("--k", type=int, default=10)

    search_cmd = subparsers.add_parser("search", help="Run daemon-backed regex search query")
    search_cmd.add_argument("--repo", "--project", dest="project", required=True)
    search_cmd.add_argument("--pattern", required=True)
    search_cmd.add_argument("--max-results", type=int, default=100)

    status_cmd = subparsers.add_parser("status", help="Show daemon status for a project")
    status_cmd.add_argument("--repo", "--project", dest="project", required=True)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    apply_containment_patches(include_mcp=True)
    import tldr.mcp_server as mcp_mod

    project = _resolve_project(args.project)

    if args.command == "context":
        result = mcp_mod.context(
            project=project,
            entry=args.entry,
            depth=args.depth,
            language=args.language,
        )
    elif args.command == "semantic":
        result = mcp_mod.semantic(
            project=project,
            query=args.query,
            k=args.k,
        )
    elif args.command == "search":
        result = mcp_mod.search(
            project=project,
            pattern=args.pattern,
            max_results=args.max_results,
        )
    elif args.command == "status":
        result = mcp_mod.status(project=project)
    else:  # pragma: no cover
        parser.error(f"unsupported command: {args.command}")
        return 2

    print(_json_or_text(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
