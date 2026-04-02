#!/usr/bin/env python3
"""Direct launcher for the contained llm-tldr MCP server.

Resolves the llm-tldr tool interpreter from the installed entrypoint shebang,
then execs tldr-mcp-contained.py under that interpreter to avoid shell-layer
stdio quirks in some MCP clients.
"""

from __future__ import annotations

import os
import shlex
import shutil
import sys
from pathlib import Path


def _resolve_llm_tldr_bin() -> Path:
    candidate = os.environ.get("LLM_TLDR_BIN")
    if candidate:
        p = Path(candidate).expanduser()
        if p.exists():
            return p.resolve()
        raise RuntimeError(f"LLM_TLDR_BIN does not exist: {candidate}")

    found = shutil.which("llm-tldr")
    if not found:
        raise RuntimeError("llm-tldr not found on PATH")
    return Path(found).resolve()


def _resolve_interpreter(entrypoint: Path) -> str:
    first = entrypoint.read_text(encoding="utf-8", errors="replace").splitlines()[0]
    if not first.startswith("#!"):
        raise RuntimeError(f"invalid shebang in {entrypoint}")

    shebang = first[2:].strip()
    if not shebang:
        raise RuntimeError(f"empty shebang in {entrypoint}")

    parts = shlex.split(shebang)
    if not parts:
        raise RuntimeError(f"unparseable shebang in {entrypoint}: {shebang!r}")

    head = parts[0]
    if Path(head).name == "env":
        if len(parts) < 2:
            raise RuntimeError(f"env shebang missing target in {entrypoint}: {shebang!r}")
        resolved = shutil.which(parts[1])
        if not resolved:
            raise RuntimeError(f"unable to resolve interpreter from env shebang: {shebang!r}")
        return resolved

    return head


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    target = script_dir / "tldr-mcp-contained.py"
    if not target.exists():
        raise RuntimeError(f"missing contained MCP entrypoint: {target}")

    llm_tldr_bin = _resolve_llm_tldr_bin()
    interpreter = _resolve_interpreter(llm_tldr_bin)

    os.execv(interpreter, [interpreter, str(target), *sys.argv[1:]])


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"tldr-mcp-contained-launch.py: {exc}", file=sys.stderr)
        raise SystemExit(1)
