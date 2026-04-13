"""
Shared Beads CLI adapter for dx-loop control-plane calls.

Runtime defaults:
- use `bdx` as command surface
- ensure BEADS_DIR points at the canonical runtime
- execute from a non-app control-plane cwd by default
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Dict, Iterable, List, Optional

DEFAULT_BEADS_DIR = str(Path.home() / ".beads-runtime" / ".beads")
DEFAULT_CONTROL_CWD = Path.home()


def resolve_beads_bin() -> str:
    """Resolve the Beads executable for dx-loop runtime calls."""
    return (
        os.environ.get("DX_LOOP_BEADS_BIN")
        or os.environ.get("BDX_BIN")
        or "bdx"
    )


def control_plane_cwd() -> Path:
    """Return the default cwd for dx-loop control-plane commands."""
    cwd = os.environ.get("DX_LOOP_CONTROL_CWD")
    if cwd:
        return Path(cwd).expanduser()
    return DEFAULT_CONTROL_CWD


def beads_subprocess_env(base_env: Optional[Dict[str, str]] = None) -> Dict[str, str]:
    """Return subprocess env with canonical BEADS_DIR defaulted."""
    env = dict(base_env or os.environ)
    env.setdefault("BEADS_DIR", DEFAULT_BEADS_DIR)
    return env


def beads_command(args: Iterable[str]) -> List[str]:
    """Build a Beads command invocation with the configured executable."""
    return [resolve_beads_bin(), *list(args)]
