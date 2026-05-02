#!/usr/bin/env python3
"""Wrapper for optional warmed semantic hints via ccc."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

UNAVAILABLE_MESSAGE = "semantic index unavailable; use rg."
DEFAULT_STATUS_TIMEOUT_SECONDS = 5
DEFAULT_SEARCH_TIMEOUT_SECONDS = 15
DEFAULT_LIMIT = 10
DEFAULT_INDEX_ROOT = Path("~/.cache/agent-semantic-indexes").expanduser()
EXPECTED_SCHEMA_VERSION = 1


@dataclass
class RepoConfig:
    repo_name: str
    canonical_path: Path
    index_root: Path
    source_branch: str


@dataclass
class ResolvedRepo:
    repo_name: str
    target_repo: Path
    canonical_path: Path
    index_root: Path
    source_branch: str


def _run(
    args: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    timeout: int = 5,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout,
    )


def _resolve_repo_configs(config_path: Path) -> dict[str, RepoConfig]:
    if not config_path.exists():
        return {}
    payload = json.loads(config_path.read_text(encoding="utf-8"))
    default_index_root = Path(str(payload.get("default_index_root", DEFAULT_INDEX_ROOT))).expanduser().resolve()
    repos = payload.get("repositories", payload)
    if not isinstance(repos, dict):
        return {}

    out: dict[str, RepoConfig] = {}
    for repo_name, raw in repos.items():
        if not isinstance(raw, dict):
            continue
        canonical = raw.get("canonical_path")
        if not canonical:
            continue
        canonical_path = Path(str(canonical)).expanduser().resolve()
        index_root = Path(str(raw.get("index_root", default_index_root / repo_name))).expanduser().resolve()
        source_branch = str(raw.get("source_branch", "master"))
        out[repo_name] = RepoConfig(
            repo_name=repo_name,
            canonical_path=canonical_path,
            index_root=index_root,
            source_branch=source_branch,
        )
    return out


def _resolve_repo(repo_path: str, repo_configs: dict[str, RepoConfig]) -> ResolvedRepo | None:
    target_repo = Path(repo_path).expanduser().resolve()
    path_parts = target_repo.parts

    # /tmp/agents/<beads-id>/<repo-name> => resolve by exact allowlisted basename
    if len(path_parts) >= 5 and path_parts[:3] == ("/", "tmp", "agents"):
        repo_name = path_parts[4]
        cfg = repo_configs.get(repo_name)
        if cfg:
            return ResolvedRepo(repo_name, target_repo, cfg.canonical_path, cfg.index_root, cfg.source_branch)

    # canonical path must match exact realpath
    matches = [cfg for cfg in repo_configs.values() if cfg.canonical_path == target_repo]
    if len(matches) == 1:
        cfg = matches[0]
        return ResolvedRepo(cfg.repo_name, target_repo, cfg.canonical_path, cfg.index_root, cfg.source_branch)

    return None


def _state_path(resolved: ResolvedRepo) -> Path:
    return resolved.index_root / "state.json"


def _index_surface(resolved: ResolvedRepo) -> Path:
    return resolved.index_root / "repo"


def _coco_dir(resolved: ResolvedRepo) -> Path:
    return resolved.index_root / "coco-global"


def _ccc_project_dir(resolved: ResolvedRepo) -> Path:
    return _index_surface(resolved) / ".cocoindex_code"


def _db_candidates(resolved: ResolvedRepo) -> list[Path]:
    return [
        _ccc_project_dir(resolved) / "target_sqlite.db",
        _coco_dir(resolved) / "target_sqlite.db",
    ]


def _settings_candidates(resolved: ResolvedRepo) -> list[Path]:
    return [
        _ccc_project_dir(resolved) / "settings.yml",
        _coco_dir(resolved) / "settings.yml",
    ]


def _lock_path(resolved: ResolvedRepo) -> Path:
    return resolved.index_root / "refresh.lock"


def _scoped_env(resolved: ResolvedRepo) -> dict[str, str]:
    env = dict(os.environ)
    env["COCOINDEX_CODE_DIR"] = str(_coco_dir(resolved))
    return env


def _refresh_lock_active(resolved: ResolvedRepo) -> bool:
    path = _lock_path(resolved)
    if not path.exists():
        return False
    try:
        with path.open("a+") as handle:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_SH | fcntl.LOCK_NB)
            except BlockingIOError:
                return True
            finally:
                try:
                    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
                except OSError:
                    pass
    except OSError:
        return True
    return False


def _load_state(resolved: ResolvedRepo) -> dict | None:
    path = _state_path(resolved)
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def _git_head(path: Path, *, timeout: int = 5) -> str | None:
    try:
        cp = _run(["git", "-C", str(path), "rev-parse", "HEAD"], timeout=timeout)
    except Exception:
        return None
    if cp.returncode != 0:
        return None
    head = cp.stdout.strip()
    return head if head else None


def _is_dirty(path: Path) -> bool:
    try:
        cp = _run(["git", "-C", str(path), "status", "--porcelain"], timeout=5)
    except Exception:
        return False
    return bool(cp.stdout.strip())


def _is_ancestor(older: str, newer: str, repo: Path) -> bool:
    try:
        cp = _run(["git", "-C", str(repo), "merge-base", "--is-ancestor", older, newer], timeout=5)
    except Exception:
        return False
    return cp.returncode == 0


def _ccc_status(ccc_bin: str, resolved: ResolvedRepo, timeout_seconds: int) -> tuple[bool, str]:
    try:
        cp = _run(
            [ccc_bin, "status"],
            cwd=_index_surface(resolved),
            env=_scoped_env(resolved),
            timeout=max(1, timeout_seconds),
        )
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except OSError:
        return False, "missing"
    combined = f"{cp.stdout}\n{cp.stderr}".lower()
    if "indexing" in combined:
        return False, "indexing"
    if cp.returncode != 0:
        return False, "failed"
    return True, "ok"


def classify_status(resolved: ResolvedRepo, *, ccc_bin: str, status_timeout_seconds: int) -> str:
    if _refresh_lock_active(resolved):
        return "indexing"
    if not _index_surface(resolved).is_dir():
        return "missing"
    if not any(path.exists() for path in _settings_candidates(resolved)):
        return "missing"
    if not any(path.exists() for path in _db_candidates(resolved)):
        return "missing"

    state = _load_state(resolved)
    if not state:
        return "missing"
    if state.get("schema_version") != EXPECTED_SCHEMA_VERSION:
        return "stale"
    if state.get("status") != "success":
        return "stale"

    indexed_head = state.get("indexed_head")
    if not isinstance(indexed_head, str) or len(indexed_head) != 40:
        return "stale"
    if state.get("repo_name") != resolved.repo_name:
        return "stale"

    # Dirty worktrees are always stale; canonical refresh baseline only.
    if resolved.target_repo != resolved.canonical_path and _is_dirty(resolved.target_repo):
        return "stale"

    canonical_head = _git_head(resolved.canonical_path)
    target_head = _git_head(resolved.target_repo)
    if not canonical_head or not target_head:
        return "stale"
    if canonical_head != indexed_head:
        return "stale"

    if target_head != indexed_head and not _is_ancestor(indexed_head, target_head, resolved.target_repo):
        return "stale"

    ok, reason = _ccc_status(ccc_bin, resolved, status_timeout_seconds)
    if not ok:
        if reason == "timeout" or reason == "indexing":
            return "indexing"
        if reason == "missing":
            return "missing"
        return "stale"
    return "ready"


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="semantic-search", description="Optional semantic hints wrapper.")
    parser.add_argument(
        "--config",
        default="configs/semantic-index/repositories.json",
        help="Semantic index repository mapping file.",
    )
    parser.add_argument("--ccc-bin", default=os.environ.get("SEMANTIC_SEARCH_CCC_BIN", "ccc"))
    parser.add_argument("--status-timeout", type=int, default=DEFAULT_STATUS_TIMEOUT_SECONDS)
    parser.add_argument("--search-timeout", type=int, default=DEFAULT_SEARCH_TIMEOUT_SECONDS)

    sub = parser.add_subparsers(dest="command", required=True)
    p_status = sub.add_parser("status")
    p_status.add_argument("--repo", required=True)

    p_query = sub.add_parser("query")
    p_query.add_argument("--repo", required=True)
    p_query.add_argument("query")
    p_query.add_argument("--limit", type=int, default=DEFAULT_LIMIT)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    repo_configs = _resolve_repo_configs(Path(args.config).expanduser().resolve())
    resolved = _resolve_repo(args.repo, repo_configs)
    status = "missing"
    if resolved:
        status = classify_status(
            resolved,
            ccc_bin=args.ccc_bin,
            status_timeout_seconds=max(1, args.status_timeout),
        )

    if args.command == "status":
        print(status)
        return 0

    if status != "ready" or not resolved:
        print(UNAVAILABLE_MESSAGE, file=sys.stderr)
        return 2

    try:
        cp = _run(
            [args.ccc_bin, "search", args.query, "--limit", str(args.limit)],
            cwd=_index_surface(resolved),
            env=_scoped_env(resolved),
            timeout=max(1, args.search_timeout),
        )
    except (subprocess.TimeoutExpired, OSError):
        print(UNAVAILABLE_MESSAGE, file=sys.stderr)
        return 2

    head_line = f"indexed_head={_load_state(resolved).get('indexed_head','unknown')}"
    print(head_line, file=sys.stderr)
    usable = bool(cp.stdout.strip())
    if cp.stdout:
        print(cp.stdout, end="")
    if cp.stderr:
        print(cp.stderr, end="", file=sys.stderr)
    if not usable:
        print(UNAVAILABLE_MESSAGE, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
