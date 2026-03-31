#!/usr/bin/env python3
"""
tldr-mcp-contained — Contained MCP server for llm-tldr.

Drop-in replacement for tldr-mcp that redirects .tldr/ and .tldrignore
to $TLDR_STATE_HOME/<project-hash>/ via symlinks before the daemon writes them.

Usage (MCP config):
  "command": ["python3", "/path/to/tldr-mcp-contained.py"]
  "args": []

Or via shell wrapper:
  "command": "/path/to/tldr-mcp-contained.sh"
  "args": []
"""

import os
import sys
from pathlib import Path

STATE_HOME = Path(
    os.environ.get("TLDR_STATE_HOME", Path.home() / ".cache" / "tldr-state")
)


def _ensure_symlinks(project_root: str) -> None:
    pr = Path(project_root).resolve()
    h = __import__("hashlib").md5(str(pr).encode()).hexdigest()
    sd = STATE_HOME / h
    tt = sd / ".tldr"
    ti = sd / ".tldrignore"
    tt.mkdir(parents=True, exist_ok=True)
    ti.parent.mkdir(parents=True, exist_ok=True)

    pt = pr / ".tldr"
    pi = pr / ".tldrignore"

    if not pt.exists():
        pt.symlink_to(tt)
    elif not pt.is_symlink():
        import shutil

        if pt.is_dir():
            shutil.rmtree(str(pt))
        else:
            pt.unlink()
        pt.symlink_to(tt)

    if not pi.exists():
        pi.symlink_to(ti)
    elif not pi.is_symlink():
        import shutil

        try:
            shutil.move(str(pi), str(ti))
        except Exception:
            pi.unlink()
        pi.symlink_to(ti)


def _apply_patches() -> None:
    import tldr.daemon.core as core_mod
    import tldr.tldrignore as tldrignore_mod

    orig_init = core_mod.DaemonCore.__init__

    def patched_init(self, project_path):
        _ensure_symlinks(str(project_path))
        orig_init(self, project_path)

    core_mod.DaemonCore.__init__ = patched_init

    tldrignore_mod.ensure_tldrignore = lambda project_dir: _ensure_symlinks(
        str(project_dir)
    )

    try:
        import tldr.semantic as semantic_mod

        semantic_mod.ensure_tldrignore = lambda project_dir: _ensure_symlinks(
            str(project_dir)
        )
    except (ImportError, AttributeError):
        pass


if __name__ == "__main__":
    _apply_patches()
    from tldr.mcp_server import main

    main()
