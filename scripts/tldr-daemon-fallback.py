#!/usr/bin/env python3
"""Daemon-backed llm-tldr fallback helper for MCP hydration gaps.

This helper intentionally uses tldr.mcp_server tool functions so calls flow
through `_send_command(...)` and daemon socket transport, matching the MCP
fast path instead of plain CLI direct API calls.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from tldr_contained_runtime import apply_containment_patches


SEMANTIC_AUTOBUILD_ENV = "TLDR_FALLBACK_SEMANTIC_AUTOBUILD"
DEFAULT_FALLBACK_SEMANTIC_MODEL = "all-MiniLM-L6-v2"


def _json_or_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    try:
        return json.dumps(value, indent=2, sort_keys=True)
    except TypeError:
        return str(value)


def _resolve_project(project: str) -> str:
    return str(Path(project).expanduser().resolve())


def _resolve_path(path_value: str) -> str:
    return str(Path(path_value).expanduser().resolve())


def _semantic_autobuild_enabled() -> bool:
    return os.environ.get(SEMANTIC_AUTOBUILD_ENV, "").lower() in {
        "1",
        "true",
        "yes",
        "on",
    }


def _semantic_index_missing_result(project: str) -> dict[str, Any]:
    try:
        from tldr_contained_runtime import _semantic_index_files

        index_file, metadata_file = _semantic_index_files(project)
        index_path = str(index_file)
        metadata_path = str(metadata_file)
    except Exception:
        index_path = None
        metadata_path = None

    next_command = (
        "~/agent-skills/scripts/tldr-contained.sh semantic index "
        f"{project} --model {DEFAULT_FALLBACK_SEMANTIC_MODEL}"
    )
    return {
        "ok": False,
        "status": "error",
        "reason_code": "semantic_index_missing",
        "message": (
            "llm-tldr semantic fallback index is missing. The daemon fallback "
            "does not auto-build semantic indexes by default because first-build "
            "can exceed agent timeouts. Run the prewarm command or fall back to "
            "targeted rg/direct reads for this turn."
        ),
        "project": project,
        "index_file": index_path,
        "metadata_file": metadata_path,
        "next_command": next_command,
        "temporary_fallback": "Use targeted rg/direct source reads if the task is urgent.",
        "autobuild_override": f"{SEMANTIC_AUTOBUILD_ENV}=1",
    }


def _semantic_index_ready(project: str) -> bool:
    try:
        from tldr_contained_runtime import _semantic_index_ready as contained_index_ready

        return bool(contained_index_ready(project))
    except Exception:
        return False


def _add_project_arg(command_parser: argparse.ArgumentParser) -> None:
    command_parser.add_argument(
        "--repo",
        "--project",
        dest="project",
        default=".",
        help="Project/repo root path (default: current directory).",
    )


def _add_language_arg(command_parser: argparse.ArgumentParser) -> None:
    command_parser.add_argument(
        "--language",
        default="python",
        help="Language identifier expected by llm-tldr (default: python).",
    )


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
    _add_project_arg(context_cmd)
    context_cmd.add_argument("--entry", required=True)
    context_cmd.add_argument("--depth", type=int, default=2)
    _add_language_arg(context_cmd)

    semantic_cmd = subparsers.add_parser("semantic", help="Run daemon-backed semantic query")
    _add_project_arg(semantic_cmd)
    semantic_cmd.add_argument("--query", required=True)
    semantic_cmd.add_argument("--k", type=int, default=10)

    search_cmd = subparsers.add_parser("search", help="Run daemon-backed regex search query")
    _add_project_arg(search_cmd)
    search_cmd.add_argument("--pattern", required=True)
    search_cmd.add_argument("--max-results", type=int, default=100)

    tree_cmd = subparsers.add_parser("tree", help="Run daemon-backed file tree query")
    _add_project_arg(tree_cmd)
    tree_cmd.add_argument(
        "--extension",
        dest="extensions",
        action="append",
        help="Optional extension filter (repeatable, e.g. --extension .py).",
    )

    structure_cmd = subparsers.add_parser(
        "structure", help="Run daemon-backed code structure query"
    )
    _add_project_arg(structure_cmd)
    _add_language_arg(structure_cmd)
    structure_cmd.add_argument("--max-results", type=int, default=100)

    extract_cmd = subparsers.add_parser(
        "extract", help="Run daemon-backed single-file structure extraction"
    )
    extract_cmd.add_argument("--file", required=True)

    cfg_cmd = subparsers.add_parser("cfg", help="Run daemon-backed control-flow analysis")
    cfg_cmd.add_argument("--file", required=True)
    cfg_cmd.add_argument("--function", required=True)
    _add_language_arg(cfg_cmd)

    dfg_cmd = subparsers.add_parser("dfg", help="Run daemon-backed data-flow analysis")
    dfg_cmd.add_argument("--file", required=True)
    dfg_cmd.add_argument("--function", required=True)
    _add_language_arg(dfg_cmd)

    slice_cmd = subparsers.add_parser("slice", help="Run daemon-backed program slice query")
    slice_cmd.add_argument("--file", required=True)
    slice_cmd.add_argument("--function", required=True)
    slice_cmd.add_argument("--line", type=int, required=True)
    slice_cmd.add_argument(
        "--direction",
        choices=("backward", "forward"),
        default="backward",
    )
    slice_cmd.add_argument("--variable")
    _add_language_arg(slice_cmd)

    impact_cmd = subparsers.add_parser(
        "impact", help="Run daemon-backed reverse call-impact query"
    )
    _add_project_arg(impact_cmd)
    impact_cmd.add_argument("--function", required=True)

    dead_cmd = subparsers.add_parser("dead", help="Run daemon-backed dead-code analysis")
    _add_project_arg(dead_cmd)
    dead_cmd.add_argument(
        "--entry-point",
        dest="entry_points",
        action="append",
        help="Entry point pattern (repeatable).",
    )
    _add_language_arg(dead_cmd)

    arch_cmd = subparsers.add_parser(
        "arch", help="Run daemon-backed architecture layer analysis"
    )
    _add_project_arg(arch_cmd)
    _add_language_arg(arch_cmd)

    calls_cmd = subparsers.add_parser("calls", help="Run daemon-backed call graph analysis")
    _add_project_arg(calls_cmd)
    _add_language_arg(calls_cmd)

    imports_cmd = subparsers.add_parser("imports", help="Run daemon-backed import analysis")
    imports_cmd.add_argument("--file", required=True)
    _add_language_arg(imports_cmd)

    importers_cmd = subparsers.add_parser(
        "importers", help="Run daemon-backed reverse import analysis"
    )
    _add_project_arg(importers_cmd)
    importers_cmd.add_argument("--module", required=True)
    _add_language_arg(importers_cmd)

    diagnostics_cmd = subparsers.add_parser(
        "diagnostics", help="Run daemon-backed diagnostics for file or directory"
    )
    diagnostics_cmd.add_argument("--path", required=True)
    _add_language_arg(diagnostics_cmd)

    change_impact_cmd = subparsers.add_parser(
        "change-impact",
        aliases=["change_impact"],
        help="Run daemon-backed changed-file impact analysis",
    )
    _add_project_arg(change_impact_cmd)
    change_impact_cmd.add_argument(
        "--file",
        dest="files",
        action="append",
        help="Changed file path (repeatable). If omitted, daemon auto-detects.",
    )

    status_cmd = subparsers.add_parser("status", help="Show daemon status for a project")
    _add_project_arg(status_cmd)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    apply_containment_patches(include_mcp=True)
    import tldr.mcp_server as mcp_mod

    command = args.command.replace("-", "_")

    if command == "context":
        project = _resolve_project(args.project)
        result = mcp_mod.context(
            project=project,
            entry=args.entry,
            depth=args.depth,
            language=args.language,
        )
    elif command == "semantic":
        project = _resolve_project(args.project)
        if not _semantic_index_ready(project) and not _semantic_autobuild_enabled():
            result = _semantic_index_missing_result(project)
            print(_json_or_text(result))
            return 3
        if _semantic_autobuild_enabled():
            os.environ.setdefault(
                "TLDR_SEMANTIC_AUTOBUILD_MODEL",
                DEFAULT_FALLBACK_SEMANTIC_MODEL,
            )
        result = mcp_mod.semantic(project=project, query=args.query, k=args.k)
    elif command == "search":
        project = _resolve_project(args.project)
        result = mcp_mod.search(
            project=project,
            pattern=args.pattern,
            max_results=args.max_results,
        )
    elif command == "tree":
        project = _resolve_project(args.project)
        result = mcp_mod.tree(project=project, extensions=args.extensions)
    elif command == "structure":
        project = _resolve_project(args.project)
        result = mcp_mod.structure(
            project=project,
            language=args.language,
            max_results=args.max_results,
        )
    elif command == "extract":
        result = mcp_mod.extract(file=_resolve_path(args.file))
    elif command == "cfg":
        result = mcp_mod.cfg(
            file=_resolve_path(args.file),
            function=args.function,
            language=args.language,
        )
    elif command == "dfg":
        result = mcp_mod.dfg(
            file=_resolve_path(args.file),
            function=args.function,
            language=args.language,
        )
    elif command == "slice":
        result = mcp_mod.slice(
            file=_resolve_path(args.file),
            function=args.function,
            line=args.line,
            direction=args.direction,
            variable=args.variable,
            language=args.language,
        )
    elif command == "impact":
        project = _resolve_project(args.project)
        result = mcp_mod.impact(project=project, function=args.function)
    elif command == "dead":
        project = _resolve_project(args.project)
        result = mcp_mod.dead(
            project=project,
            entry_points=args.entry_points,
            language=args.language,
        )
    elif command == "arch":
        project = _resolve_project(args.project)
        result = mcp_mod.arch(project=project, language=args.language)
    elif command == "calls":
        project = _resolve_project(args.project)
        result = mcp_mod.calls(project=project, language=args.language)
    elif command == "imports":
        result = mcp_mod.imports(file=_resolve_path(args.file), language=args.language)
    elif command == "importers":
        project = _resolve_project(args.project)
        result = mcp_mod.importers(
            project=project,
            module=args.module,
            language=args.language,
        )
    elif command == "diagnostics":
        result = mcp_mod.diagnostics(path=_resolve_path(args.path), language=args.language)
    elif command == "change_impact":
        project = _resolve_project(args.project)
        files = [_resolve_path(file_path) for file_path in args.files] if args.files else None
        result = mcp_mod.change_impact(project=project, files=files)
    elif command == "status":
        project = _resolve_project(args.project)
        result = mcp_mod.status(project=project)
    else:  # pragma: no cover
        parser.error(f"unsupported command: {command}")
        return 2

    print(_json_or_text(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
