#!/usr/bin/env python3
"""Runtime containment shim for llm-tldr.

This module enforces literal no-in-repo containment for `.tldr` and
`.tldrignore` by rewriting those path joins to an external state home.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path, PurePath
from typing import Any, Iterator


STATE_HOME = Path(
    os.environ.get("TLDR_STATE_HOME", Path.home() / ".cache" / "tldr-state")
).expanduser()

_PATCHED_BASE = False
_PATCHED_MCP = False
_PATCHED_SEMANTIC = False
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


def _semantic_bootstrap_lock_path(project_path: str | Path) -> Path:
    bucket = _state_bucket(Path(project_path))
    bucket.mkdir(parents=True, exist_ok=True)
    return bucket / ".semantic-bootstrap.lock"


@contextmanager
def _semantic_bootstrap_lock(project_path: str | Path) -> Iterator[None]:
    lock_path = _semantic_bootstrap_lock_path(project_path)
    with open(lock_path, "w") as lock_file:
        if os.name == "nt":
            import msvcrt

            while True:
                try:
                    msvcrt.locking(lock_file.fileno(), msvcrt.LK_LOCK, 1)
                    break
                except OSError:
                    time.sleep(0.1)
            try:
                yield
            finally:
                msvcrt.locking(lock_file.fileno(), msvcrt.LK_UNLCK, 1)
            return

        import fcntl

        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


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

                helper = Path(__file__).with_name("tldr-contained-daemon.py")
                popen_kwargs: dict[str, Any] = {
                    "stdout": subprocess.DEVNULL,
                    "stderr": subprocess.DEVNULL,
                }
                if _os.name == "nt":
                    popen_kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
                else:
                    popen_kwargs["start_new_session"] = True

                subprocess.Popen(
                    [sys.executable, str(helper), project],
                    **popen_kwargs,
                )

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


def _bootstrap_semantic_index(
    *,
    build_semantic_index: Any,
    project_path: str,
    model: str | None,
) -> None:
    lang = os.environ.get("TLDR_SEMANTIC_AUTOBUILD_LANG", "all")
    bootstrap_model = model or os.environ.get("TLDR_SEMANTIC_AUTOBUILD_MODEL")
    build_semantic_index(
        str(Path(project_path).resolve()),
        lang=lang,
        model=bootstrap_model,
        show_progress=False,
    )


def _semantic_index_files(project_path: str | Path) -> tuple[Path, Path]:
    import tldr.semantic as semantic_mod

    project_root = semantic_mod._find_project_root(Path(project_path).resolve())
    cache_dir = project_root / ".tldr" / "cache" / "semantic"
    return cache_dir / "index.faiss", cache_dir / "metadata.json"


def _semantic_index_ready(project_path: str | Path) -> bool:
    index_file, metadata_file = _semantic_index_files(project_path)
    return index_file.exists() and metadata_file.exists()


def _semantic_index_missing_error(exc: FileNotFoundError) -> bool:
    message = str(exc)
    return (
        "Semantic index not found" in message
        or "Metadata not found" in message
    )


def _ensure_semantic_bootstrap(
    *,
    build_semantic_index: Any,
    semantic_search: Any,
    project_path: str,
    query: str,
    k: int,
    expand_graph: bool,
    model: str | None,
):
    try:
        return semantic_search(
            project_path,
            query,
            k=k,
            expand_graph=expand_graph,
            model=model,
        )
    except FileNotFoundError as exc:
        if not _semantic_index_missing_error(exc):
            raise

    with _semantic_bootstrap_lock(project_path):
        try:
            return semantic_search(
                project_path,
                query,
                k=k,
                expand_graph=expand_graph,
                model=model,
            )
        except FileNotFoundError as exc:
            if not _semantic_index_missing_error(exc):
                raise

        try:
            _bootstrap_semantic_index(
                build_semantic_index=build_semantic_index,
                project_path=project_path,
                model=model,
            )
        except Exception as build_exc:
            raise RuntimeError(
                f"Semantic index missing and contained auto-bootstrap failed for {Path(project_path).resolve()}: {build_exc}"
            ) from build_exc

        return semantic_search(
            project_path,
            query,
            k=k,
            expand_graph=expand_graph,
            model=model,
        )


def _patch_semantic_autobootstrap() -> None:
    import tldr.semantic as semantic_mod
    import tldr.mcp_server as mcp_mod

    original_search = semantic_mod.semantic_search
    original_build = semantic_mod.build_semantic_index
    original_send_command = mcp_mod._send_command

    def _contained_semantic_search(
        project_path: str,
        query: str,
        k: int = 5,
        expand_graph: bool = False,
        model: str | None = None,
    ):
        return _ensure_semantic_bootstrap(
            build_semantic_index=original_build,
            semantic_search=original_search,
            project_path=project_path,
            query=query,
            k=k,
            expand_graph=expand_graph,
            model=model,
        )

    def _contained_send_command(project: str, command: dict) -> dict:
        if command.get("cmd") == "semantic" and command.get("action", "search") == "search":
            with _semantic_bootstrap_lock(project):
                if not _semantic_index_ready(project):
                    _bootstrap_semantic_index(
                        build_semantic_index=original_build,
                        project_path=project,
                        model=os.environ.get("TLDR_SEMANTIC_AUTOBUILD_MODEL"),
                    )
        last_error: Exception | None = None
        for attempt in range(3):
            try:
                return original_send_command(project, command)
            except json.JSONDecodeError as exc:
                last_error = exc
                if command.get("cmd") != "semantic":
                    raise
                time.sleep(0.2 * (attempt + 1))
        if last_error is not None:
            raise last_error
        return original_send_command(project, command)

    semantic_mod.semantic_search = _contained_semantic_search
    mcp_mod._send_command = _contained_send_command


def apply_containment_patches(*, include_mcp: bool) -> None:
    global _PATCHED_BASE
    global _PATCHED_MCP
    global _PATCHED_SEMANTIC

    if not _PATCHED_BASE:
        STATE_HOME.mkdir(parents=True, exist_ok=True)
        _patch_path_join()
        _patch_semantic_markers()
        _PATCHED_BASE = True

    if not _PATCHED_SEMANTIC:
        _patch_semantic_autobootstrap()
        _PATCHED_SEMANTIC = True

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


def run_daemon(project_path: str) -> int:
    apply_containment_patches(include_mcp=False)
    from tldr.daemon.startup import start_daemon

    start_daemon(project_path, foreground=True)
    return 0
