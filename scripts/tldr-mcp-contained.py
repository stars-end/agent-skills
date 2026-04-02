#!/usr/bin/env python3
"""Contained MCP server entrypoint for llm-tldr.

This wrapper keeps the native llm-tldr MCP server unchanged, but adapts stdio
transport so both JSONL-speaking clients and Content-Length framed clients can
talk to it. OpenCode currently uses JSONL; Codex expects framed MCP stdio.
"""

from __future__ import annotations

import subprocess
import sys
import threading
from pathlib import Path

from tldr_contained_runtime import run_mcp


_NATIVE_FLAG = "--native-jsonl-server"


def _spawn_native_server() -> subprocess.Popen[bytes]:
    script = Path(__file__).resolve()
    return subprocess.Popen(
        [sys.executable, str(script), _NATIVE_FLAG],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=sys.stderr,
        bufsize=0,
    )


def _read_framed_body(stdin, first_header: bytes | None = None) -> bytes | None:
    header_line = first_header if first_header is not None else stdin.readline()
    if not header_line:
        return None

    content_length: int | None = None
    line = header_line
    while line not in {b"\n", b"\r\n", b""}:
        if line.lower().startswith(b"content-length:"):
            try:
                content_length = int(line.split(b":", 1)[1].strip())
            except ValueError as exc:
                raise RuntimeError(f"invalid Content-Length header: {line!r}") from exc
        line = stdin.readline()

    if content_length is None:
        raise RuntimeError("missing Content-Length header in framed MCP request")

    body = stdin.read(content_length)
    if len(body) != content_length:
        raise RuntimeError(
            f"incomplete MCP body: expected {content_length} bytes, got {len(body)}"
        )
    return body


def _bridge_child_output(
    child_stdout,
    parent_stdout,
    *,
    framed: bool,
) -> None:
    try:
        while True:
            line = child_stdout.readline()
            if not line:
                break
            if framed:
                body = line.rstrip(b"\r\n")
                if not body:
                    continue
                header = f"Content-Length: {len(body)}\r\n\r\n".encode("utf-8")
                parent_stdout.write(header)
                parent_stdout.write(body)
            else:
                parent_stdout.write(line)
            parent_stdout.flush()
    finally:
        try:
            child_stdout.close()
        except Exception:
            pass


def _run_transport_bridge() -> int:
    stdin = sys.stdin.buffer
    stdout = sys.stdout.buffer

    first_line = stdin.readline()
    if not first_line:
        return 0

    framed = first_line.lstrip().startswith(b"Content-Length:")
    child = _spawn_native_server()
    assert child.stdin is not None
    assert child.stdout is not None

    output_thread = threading.Thread(
        target=_bridge_child_output,
        args=(child.stdout, stdout),
        kwargs={"framed": framed},
        daemon=True,
    )
    output_thread.start()

    try:
        if framed:
            header_line: bytes | None = first_line
            while True:
                body = _read_framed_body(stdin, header_line)
                if body is None:
                    break
                child.stdin.write(body + b"\n")
                child.stdin.flush()
                header_line = None
        else:
            line = first_line
            while line:
                if not line.endswith(b"\n"):
                    line += b"\n"
                child.stdin.write(line)
                child.stdin.flush()
                line = stdin.readline()
    except Exception as exc:
        print(
            f"tldr-mcp-contained transport bridge error (framed={framed}): {type(exc).__name__}: {exc}",
            file=sys.stderr,
        )
        return 1
    finally:
        try:
            child.stdin.close()
        except Exception:
            pass

    return child.wait()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == _NATIVE_FLAG:
        sys.argv = [sys.argv[0]]
        raise SystemExit(run_mcp())
    raise SystemExit(_run_transport_bridge())
