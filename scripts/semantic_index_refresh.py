#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = REPO_ROOT / "configs" / "semantic-index" / "repositories.json"


class RefreshError(RuntimeError):
    pass


@dataclass(frozen=True)
class Timeouts:
    init: int
    doctor: int
    index: int
    status: int
    daemon_stop: int


def utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Refresh canonical semantic indexes in non-canonical cache surfaces.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--repo-name", help="Allowlisted repository name")
    mode.add_argument("--all", action="store_true", help="Refresh all allowlisted repositories")
    parser.add_argument("--dry-run", action="store_true", help="Print planned operations without mutating anything")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH), help="Path to repositories config JSON")
    parser.add_argument("--index-root", help="Override index root path (defaults to config default_index_root)")
    parser.add_argument("--timeout-init", type=int, default=120)
    parser.add_argument("--timeout-doctor", type=int, default=120)
    parser.add_argument("--timeout-index", type=int, default=1800)
    parser.add_argument("--timeout-status", type=int, default=60)
    parser.add_argument("--timeout-daemon-stop", type=int, default=60)
    return parser.parse_args(argv)


def load_config(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text())
    if data.get("schema_version") != 1:
        raise RefreshError(f"unsupported repositories config schema_version: {data.get('schema_version')!r}")
    allowlist = data.get("allowlist")
    repos = data.get("repositories")
    if not isinstance(allowlist, list) or not isinstance(repos, dict):
        raise RefreshError("invalid repositories config: expected allowlist list and repositories object")
    missing = [name for name in allowlist if name not in repos]
    if missing:
        raise RefreshError(f"allowlist entries missing from repositories: {', '.join(missing)}")
    return data


def run_command(
    cmd: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    timeout: int | None = None,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(cmd, cwd=str(cwd) if cwd else None, env=env, capture_output=True, text=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired as exc:
        raise RefreshError(f"timeout: {' '.join(cmd)}") from exc


def parse_stats(text: str) -> dict[str, Any]:
    stats: dict[str, Any] = {}
    int_patterns = {
        "matched_files": r"matched files:\s*([0-9]+)",
        "chunks": r"(?:total chunks|chunks):\s*([0-9]+)",
        "db_bytes": r"(?:total size|db size):\s*([0-9]+)\s*bytes",
    }
    for key, pattern in int_patterns.items():
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            stats[key] = int(match.group(1))
    for key, pattern in {
        "ccc_version": r"cocoindex code version:\s*([^\n]+)",
        "embedding_provider": r"embedding provider:\s*([^\n]+)",
        "embedding_model": r"embedding model:\s*([^\n]+)",
    }.items():
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            stats[key] = match.group(1).strip()
    return stats


def scoped_env(coco_dir: Path) -> dict[str, str]:
    env = dict(os.environ)
    env["COCOINDEX_CODE_DIR"] = str(coco_dir)
    return env


def write_state(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def lock_file(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = path.open("a+")
    try:
        fcntl.flock(fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        fd.close()
        raise RefreshError(f"lock busy: {path}") from exc
    return fd


def cleanup_daemon(coco_dir: Path, timeouts: Timeouts) -> None:
    env = scoped_env(coco_dir)
    stop = subprocess.run(["ccc", "daemon", "stop"], env=env, capture_output=True, text=True, timeout=timeouts.daemon_stop, check=False)
    if stop.returncode == 0:
        return
    # Fallback is scoped to this COCOINDEX_CODE_DIR path pattern only.
    pids = subprocess.run(["pgrep", "-f", str(coco_dir)], capture_output=True, text=True, check=False)
    for token in pids.stdout.split():
        if token.isdigit():
            subprocess.run(["kill", "-TERM", token], capture_output=True, text=True, check=False)


def ensure_index_surface(repo_dir: Path, remote: str, branch: str) -> tuple[str, str]:
    if not repo_dir.exists():
        clone = run_command(["git", "clone", remote, str(repo_dir)])
        if clone.returncode != 0:
            raise RefreshError(f"git clone failed: {clone.stderr.strip()}")
    fetch = run_command(["git", "-C", str(repo_dir), "fetch", "origin", branch])
    if fetch.returncode != 0:
        raise RefreshError(f"git fetch failed: {fetch.stderr.strip()}")
    checkout = run_command(["git", "-C", str(repo_dir), "checkout", "-B", branch, f"origin/{branch}"])
    if checkout.returncode != 0:
        raise RefreshError(f"git checkout failed: {checkout.stderr.strip()}")
    head = run_command(["git", "-C", str(repo_dir), "rev-parse", "HEAD"])
    if head.returncode != 0:
        raise RefreshError(f"git rev-parse failed: {head.stderr.strip()}")
    current_remote = run_command(["git", "-C", str(repo_dir), "remote", "get-url", "origin"])
    return head.stdout.strip(), current_remote.stdout.strip() if current_remote.returncode == 0 else remote


def refresh_one(repo_name: str, repo_cfg: dict[str, Any], *, index_root: Path, dry_run: bool, timeouts: Timeouts) -> int:
    root = index_root / repo_name
    repo_dir = root / "repo"
    coco_dir = root / "coco-global"
    state_path = root / "state.json"
    log_path = root / "refresh.log"
    lock_path = root / "refresh.lock"
    branch = str(repo_cfg["source_branch"])
    remote = str(repo_cfg["source_remote"])
    started_at = utc_now_iso()

    if dry_run:
        print(f"DRY RUN repo={repo_name}")
        print(f"  index_root={root}")
        print(f"  repo_dir={repo_dir}")
        print(f"  coco_dir={coco_dir}")
        print(f"  would run: git clone/fetch/checkout + ccc init/doctor/index/status + ccc daemon stop")
        return 0

    lock_handle = lock_file(lock_path)
    root.mkdir(parents=True, exist_ok=True)
    coco_dir.mkdir(parents=True, exist_ok=True)
    env = scoped_env(coco_dir)
    stats: dict[str, Any] = {}
    exit_code = 1
    status = "failure"
    indexed_head = ""
    resolved_remote = remote
    error: str | None = None

    try:
        indexed_head, resolved_remote = ensure_index_surface(repo_dir, remote, branch)
        with log_path.open("a") as log:
            def logged(cmd: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
                result = run_command(cmd, cwd=repo_dir, env=env, timeout=timeout)
                log.write(f"$ {' '.join(cmd)}\n")
                if result.stdout:
                    log.write(result.stdout)
                if result.stderr:
                    log.write(result.stderr)
                log.flush()
                return result

            init = logged(["ccc", "init", "--force"], timeouts.init)
            if init.returncode != 0:
                raise RefreshError(f"ccc init failed: {init.stderr.strip()}")
            doctor = logged(["ccc", "doctor"], timeouts.doctor)
            stats.update(parse_stats(doctor.stdout + "\n" + doctor.stderr))
            if doctor.returncode != 0:
                raise RefreshError(f"ccc doctor failed: {doctor.stderr.strip()}")
            index = logged(["ccc", "index"], timeouts.index)
            stats.update(parse_stats(index.stdout + "\n" + index.stderr))
            if index.returncode != 0:
                raise RefreshError(f"ccc index failed: {index.stderr.strip()}")
            status_result = logged(["ccc", "status"], timeouts.status)
            stats.update(parse_stats(status_result.stdout + "\n" + status_result.stderr))
            if status_result.returncode != 0:
                raise RefreshError(f"ccc status failed: {status_result.stderr.strip()}")
            db_path = coco_dir / "target_sqlite.db"
            if db_path.exists():
                stats["db_bytes"] = db_path.stat().st_size
            exit_code = 0
            status = "success"
    except RefreshError as exc:
        error = str(exc)
    finally:
        try:
            cleanup_daemon(coco_dir, timeouts)
        except subprocess.TimeoutExpired:
            error = error or "timeout: ccc daemon stop"
        finished_at = utc_now_iso()
        state = {
            "schema_version": 1,
            "repo_name": repo_name,
            "source_remote": resolved_remote,
            "source_branch": branch,
            "index_surface": str(repo_dir),
            "indexed_head": indexed_head,
            "started_at": started_at,
            "finished_at": finished_at,
            "status": status,
            "exit_code": exit_code,
            "db_bytes": int(stats.get("db_bytes", 0)),
        }
        for key in ("matched_files", "chunks", "ccc_version", "embedding_provider", "embedding_model"):
            if key in stats:
                state[key] = stats[key]
        if error:
            state["error"] = error
        write_state(state_path, state)
        lock_handle.close()

    return exit_code


def select_repos(cfg: dict[str, Any], repo_name: str | None, all_repos: bool) -> list[str]:
    allowlist = list(cfg["allowlist"])
    if all_repos:
        return allowlist
    if repo_name not in allowlist:
        raise RefreshError(f"unknown repo: {repo_name}")
    return [repo_name]


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        cfg = load_config(Path(args.config))
        repos = select_repos(cfg, args.repo_name, args.all)
    except RefreshError as err:
        print(str(err), file=sys.stderr)
        return 1
    index_root = Path(os.path.expanduser(args.index_root or cfg["default_index_root"]))
    timeouts = Timeouts(
        init=args.timeout_init,
        doctor=args.timeout_doctor,
        index=args.timeout_index,
        status=args.timeout_status,
        daemon_stop=args.timeout_daemon_stop,
    )

    exit_code = 0
    for repo in repos:
        code = refresh_one(repo, cfg["repositories"][repo], index_root=index_root, dry_run=args.dry_run, timeouts=timeouts)
        if code != 0:
            exit_code = code
    return exit_code


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RefreshError as err:
        print(str(err), file=sys.stderr)
        raise SystemExit(1)
