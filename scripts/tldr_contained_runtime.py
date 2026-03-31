#!/usr/bin/env python3
"""Runtime containment shim for llm-tldr.

This module enforces literal no-in-repo containment for `.tldr` and
`.tldrignore` by rewriting those path joins to an external state home.
"""

from __future__ import annotations

import hashlib
import os
import sys
import time
from pathlib import Path, PurePath
from typing import Any


STATE_HOME = Path(
    os.environ.get("TLDR_STATE_HOME", Path.home() / ".cache" / "tldr-state")
).expanduser()

_PATCHED_BASE = False
_PATCHED_MCP = False
_ORIG_TRUEDIV = None


def _is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _state_bucket(base: Path) -> Path:
    resolved = base.resolve()
    digest = hashlib.md5(str(resolved).encode("utf-8")).hexdigest()
    return STATE_HOME / digest


def _rewrite_special_path(base: Path, leaf: str) -> Path:
    if _is_relative_to(base.resolve(), STATE_HOME.resolve()):
        return base / leaf
    bucket = _state_bucket(base)
    bucket.mkdir(parents=True, exist_ok=True)
    return bucket / leaf


def _patch_path_join() -> None:
    global _ORIG_TRUEDIV
    if _ORIG_TRUEDIV is not None:
        return

    _ORIG_TRUEDIV = PurePath.__truediv__

    def _contained_truediv(self: PurePath, key: Any):  # type: ignore[override]
        result = _ORIG_TRUEDIV(self, key)
        key_str = str(key)
        if key_str not in {".tldr", ".tldrignore"}:
            return result
        try:
            base = Path(self)
            return _rewrite_special_path(base, key_str)
        except Exception:
            return result

    PurePath.__truediv__ = _contained_truediv  # type: ignore[assignment]


def _patch_semantic_markers() -> None:
    import tldr.semantic as semantic_mod

    semantic_mod.PROJECT_ROOT_MARKERS = [
        marker for marker in semantic_mod.PROJECT_ROOT_MARKERS if marker != ".tldr"
    ]


def _patch_mcp_daemon_startup() -> None:
    import os as _os

    import tldr.mcp_server as mcp_mod
    from tldr.daemon import start_daemon

    def _contained_ensure_daemon(project: str, timeout: float = 10.0) -> None:
        if mcp_mod._ping_daemon(project):
            return

        socket_path = mcp_mod._get_socket_path(project)
        lock_path = mcp_mod._get_lock_path(project)

        lock_path.touch(exist_ok=True)
        with open(lock_path, "w") as lock_file:
            try:
                if _os.name == "nt":
                    lock_start = time.time()
                    lock_timeout = 10.0
                    while True:
                        try:
                            mcp_mod.msvcrt.locking(lock_file.fileno(), mcp_mod.msvcrt.LK_NBLCK, 1)
                            break
                        except OSError as exc:
                            if time.time() - lock_start > lock_timeout:
                                raise RuntimeError(
                                    f"Timeout acquiring lock on {lock_path} after {lock_timeout}s"
                                ) from exc
                            time.sleep(0.1)
                else:
                    mcp_mod.fcntl.flock(lock_file.fileno(), mcp_mod.fcntl.LOCK_EX)

                if mcp_mod._ping_daemon(project):
                    return

                if socket_path.exists() and _os.name != "nt":
                    import stat

                    try:
                        if stat.S_ISSOCK(socket_path.stat().st_mode):
                            socket_path.unlink(missing_ok=True)
                    except OSError:
                        pass

                start_daemon(project, foreground=False)

                start = time.time()
                while time.time() - start < timeout:
                    if mcp_mod._ping_daemon(project):
                        return
                    time.sleep(0.1)

                raise RuntimeError(f"Failed to start TLDR daemon for {project}")
            finally:
                if _os.name == "nt":
                    try:
                        mcp_mod.msvcrt.locking(lock_file.fileno(), mcp_mod.msvcrt.LK_UNLCK, 1)
                    except OSError:
                        pass
                else:
                    mcp_mod.fcntl.flock(lock_file.fileno(), mcp_mod.fcntl.LOCK_UN)

    mcp_mod._ensure_daemon = _contained_ensure_daemon


def apply_containment_patches(*, include_mcp: bool) -> None:
    global _PATCHED_BASE
    global _PATCHED_MCP

    if not _PATCHED_BASE:
        STATE_HOME.mkdir(parents=True, exist_ok=True)
        _patch_path_join()
        _patch_semantic_markers()
        _PATCHED_BASE = True

    if include_mcp and not _PATCHED_MCP:
        _patch_mcp_daemon_startup()
        _PATCHED_MCP = True


def run_cli(argv: list[str]) -> int:
    apply_containment_patches(include_mcp=False)
    from tldr.cli import main as cli_main

    sys.argv = ["llm-tldr", *argv]
    cli_main()
    return 0


def run_mcp() -> int:
    apply_containment_patches(include_mcp=True)
    from tldr.mcp_server import main as mcp_main

    mcp_main()
    return 0
