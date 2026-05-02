#!/usr/bin/env python3
"""Thin wrapper for optional CocoIndex Code semantic hints."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


UNAVAILABLE_MESSAGE = "semantic index unavailable; use rg."
DEFAULT_STATUS_TIMEOUT_SECONDS = 5
DEFAULT_SEARCH_TIMEOUT_SECONDS = 15
DEFAULT_LIMIT = 10


def _resolve_repo(path_value: str) -> Path:
    return Path(path_value).expanduser().resolve()


def _repo_git_dir(repo: Path) -> Path:
    return repo / ".git"


def _is_repo_dirty(repo: Path) -> bool:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), "status", "--porcelain", "--untracked-files=no"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except Exception:
        return False
    return bool(result.stdout.strip())


def _max_reference_mtime(repo: Path) -> float:
    git_dir = _repo_git_dir(repo)
    candidates: list[Path] = [git_dir / "index", git_dir / "HEAD"]
    head = git_dir / "HEAD"
    try:
        head_text = head.read_text(encoding="utf-8").strip()
        if head_text.startswith("ref: "):
            candidates.append(git_dir / head_text.split("ref: ", 1)[1].strip())
    except OSError:
        pass

    mtimes: list[float] = []
    for path in candidates:
        try:
            mtimes.append(path.stat().st_mtime)
        except OSError:
            continue
    return max(mtimes) if mtimes else 0.0


def _is_stale(repo: Path, target_db: Path) -> bool:
    if _is_repo_dirty(repo):
        return True
    try:
        index_mtime = target_db.stat().st_mtime
    except OSError:
        return True
    return index_mtime < _max_reference_mtime(repo)


def _run_ccc(
    ccc_bin: str,
    repo: Path,
    args: list[str],
    *,
    timeout_seconds: int,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [ccc_bin, *args],
        cwd=str(repo),
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
        check=False,
    )


def _parse_indexing(status_output: str) -> bool:
    text = status_output.lower()
    return "indexing in progress" in text or "status: indexing" in text


def classify_status(
    repo: Path,
    *,
    ccc_bin: str,
    status_timeout_seconds: int,
) -> str:
    index_dir = repo / ".cocoindex_code"
    settings_file = index_dir / "settings.yml"
    target_db = index_dir / "target_sqlite.db"

    if not settings_file.exists() or not target_db.exists():
        return "missing"

    try:
        status_cp = _run_ccc(
            ccc_bin,
            repo,
            ["status"],
            timeout_seconds=status_timeout_seconds,
        )
    except subprocess.TimeoutExpired:
        return "indexing"
    except OSError:
        return "missing"

    combined = f"{status_cp.stdout}\n{status_cp.stderr}"
    if _parse_indexing(combined):
        return "indexing"
    if status_cp.returncode != 0:
        return "stale"
    if _is_stale(repo, target_db):
        return "stale"
    return "ready"


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="semantic-search",
        description="Optional CocoIndex Code semantic query wrapper.",
    )
    parser.add_argument(
        "--ccc-bin",
        default=os.environ.get("SEMANTIC_SEARCH_CCC_BIN", "ccc"),
        help="Path to ccc binary (default: ccc or SEMANTIC_SEARCH_CCC_BIN).",
    )
    parser.add_argument(
        "--status-timeout",
        type=int,
        default=DEFAULT_STATUS_TIMEOUT_SECONDS,
        help=f"Timeout for ccc status calls in seconds (default: {DEFAULT_STATUS_TIMEOUT_SECONDS}).",
    )
    parser.add_argument(
        "--search-timeout",
        type=int,
        default=DEFAULT_SEARCH_TIMEOUT_SECONDS,
        help=f"Timeout for ccc search calls in seconds (default: {DEFAULT_SEARCH_TIMEOUT_SECONDS}).",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    status_cmd = subparsers.add_parser("status", help="Classify semantic index state.")
    status_cmd.add_argument("--repo", default=".", help="Repository path.")

    query_cmd = subparsers.add_parser("query", help="Run semantic query when ready.")
    query_cmd.add_argument("--repo", default=".", help="Repository path.")
    query_cmd.add_argument("query", help="Natural-language query text.")
    query_cmd.add_argument(
        "--limit",
        type=int,
        default=DEFAULT_LIMIT,
        help=f"Maximum result count (default: {DEFAULT_LIMIT}).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    repo = _resolve_repo(args.repo)

    status = classify_status(
        repo,
        ccc_bin=args.ccc_bin,
        status_timeout_seconds=max(1, args.status_timeout),
    )

    if args.command == "status":
        print(status)
        return 0

    if status != "ready":
        print(UNAVAILABLE_MESSAGE, file=sys.stderr)
        return 2

    try:
        result = _run_ccc(
            args.ccc_bin,
            repo,
            ["search", args.query, "--limit", str(args.limit)],
            timeout_seconds=max(1, args.search_timeout),
        )
    except (subprocess.TimeoutExpired, OSError):
        print(UNAVAILABLE_MESSAGE, file=sys.stderr)
        return 2

    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
