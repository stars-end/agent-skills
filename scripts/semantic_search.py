#!/usr/bin/env python3
"""Wrapper for optional warmed semantic hints via ccc."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import shutil
import subprocess
import sys
import textwrap
from dataclasses import dataclass
from pathlib import Path

UNAVAILABLE_MESSAGE = "semantic index unavailable; use rg."
DEFAULT_STATUS_TIMEOUT_SECONDS = 5
DEFAULT_SEARCH_TIMEOUT_SECONDS = 15
DEFAULT_LIMIT = 10
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INDEX_ROOT = Path("~/.cache/agent-semantic-indexes").expanduser()
DEFAULT_CONFIG_PATH = REPO_ROOT / "configs" / "semantic-index" / "repositories.json"
EXPECTED_SCHEMA_VERSION = 1

DIRECT_CCC_QUERY_CODE = r"""
import asyncio
import json
import os
import sys
from pathlib import Path

from cocoindex.connectors import sqlite as coco_sqlite
from cocoindex_code.query import query_codebase
from cocoindex_code.settings import load_user_settings
from cocoindex_code.shared import EMBEDDER, QUERY_EMBED_PARAMS, SQLITE_DB, create_embedder


class _Env:
    def __init__(self, values):
        self._values = values

    def get_context(self, key):
        return self._values[key]


async def _main():
    db_path = Path(sys.argv[1])
    query = sys.argv[2]
    limit = int(sys.argv[3])

    settings = load_user_settings()
    for key, value in settings.envs.items():
        os.environ.setdefault(str(key), str(value))

    embedder = create_embedder(
        settings.embedding,
        settings.embedding.indexing_params or {},
    )
    env = _Env(
        {
            SQLITE_DB: coco_sqlite.connect(str(db_path), load_vec=True),
            EMBEDDER: embedder,
            QUERY_EMBED_PARAMS: dict(settings.embedding.query_params or {}),
        }
    )
    results = await query_codebase(query, db_path, env, limit=limit)
    print(
        json.dumps(
            [
                {
                    "file_path": item.file_path,
                    "language": item.language,
                    "content": item.content,
                    "start_line": item.start_line,
                    "end_line": item.end_line,
                    "score": item.score,
                }
                for item in results
            ],
            ensure_ascii=False,
        )
    )


asyncio.run(_main())
"""


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


def _first_existing_db(resolved: ResolvedRepo) -> Path | None:
    for path in _db_candidates(resolved):
        if path.exists():
            return path
    return None


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


def classify_status(resolved: ResolvedRepo) -> str:
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

    return "ready"


def _python_from_ccc_bin(ccc_bin: str) -> str | None:
    candidate = shutil.which(ccc_bin) if not os.path.isabs(ccc_bin) else ccc_bin
    if not candidate:
        return None
    path = Path(candidate)
    try:
        first_line = path.read_text(encoding="utf-8", errors="ignore").splitlines()[0]
    except (OSError, IndexError):
        return None
    if not first_line.startswith("#!"):
        return None
    executable = first_line[2:].strip().split()[0]
    if "python" not in Path(executable).name:
        return None
    return executable


def _format_direct_results(raw: str) -> str:
    rows = json.loads(raw)
    if not isinstance(rows, list) or not rows:
        return ""
    chunks: list[str] = []
    for idx, row in enumerate(rows, 1):
        score = float(row.get("score", 0.0))
        file_path = row.get("file_path", "")
        start = row.get("start_line", "")
        end = row.get("end_line", "")
        language = row.get("language", "")
        content = row.get("content", "")
        chunks.append(
            f"\n--- Result {idx} (score: {score:.3f}) ---\n"
            f"File: {file_path}:{start}-{end} [{language}]\n"
            f"{content}"
        )
    return "\n".join(chunks).lstrip("\n") + "\n"


def _direct_query(
    resolved: ResolvedRepo,
    *,
    ccc_bin: str,
    query: str,
    limit: int,
    timeout_seconds: int,
) -> tuple[bool, str, str]:
    db_path = _first_existing_db(resolved)
    if db_path is None:
        return False, "", "missing-db"

    env = _scoped_env(resolved)
    test_runner = os.environ.get("SEMANTIC_SEARCH_QUERY_RUNNER")
    if test_runner:
        cmd = [
            test_runner,
            "--db",
            str(db_path),
            "--repo",
            str(_index_surface(resolved)),
            "--query",
            query,
            "--limit",
            str(limit),
        ]
    else:
        ccc_python = _python_from_ccc_bin(ccc_bin)
        if not ccc_python:
            return False, "", "missing-python"
        cmd = [
            ccc_python,
            "-c",
            textwrap.dedent(DIRECT_CCC_QUERY_CODE),
            str(db_path),
            query,
            str(limit),
        ]

    try:
        cp = _run(cmd, cwd=_index_surface(resolved), env=env, timeout=max(1, timeout_seconds))
    except subprocess.TimeoutExpired:
        return False, "", "timeout"
    except OSError as exc:
        return False, "", f"failed: {exc}"
    if cp.returncode != 0:
        return False, cp.stdout, cp.stderr.strip() or "failed"

    if test_runner:
        output = cp.stdout
    else:
        try:
            output = _format_direct_results(cp.stdout)
        except (TypeError, ValueError, json.JSONDecodeError) as exc:
            return False, cp.stdout, f"invalid-results: {exc}"
    if not output.strip():
        return False, output, "empty"
    return True, output, cp.stderr


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="semantic-search", description="Optional semantic hints wrapper.")
    parser.add_argument(
        "--config",
        default=str(DEFAULT_CONFIG_PATH),
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
        status = classify_status(resolved)

    if args.command == "status":
        print(status)
        return 0

    if status != "ready" or not resolved:
        print(UNAVAILABLE_MESSAGE, file=sys.stderr)
        return 2

    ok, output, err = _direct_query(
        resolved,
        ccc_bin=args.ccc_bin,
        query=args.query,
        limit=args.limit,
        timeout_seconds=max(1, args.search_timeout),
    )

    state = _load_state(resolved) or {}
    head_line = f"indexed_head={state.get('indexed_head','unknown')}"
    print(head_line, file=sys.stderr)
    if output:
        print(output, end="")
    if err:
        print(err, end="\n" if not err.endswith("\n") else "", file=sys.stderr)
    if not ok:
        print(UNAVAILABLE_MESSAGE, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
