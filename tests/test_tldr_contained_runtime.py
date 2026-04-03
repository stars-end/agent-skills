from __future__ import annotations

import importlib.util
import json
import sys
import types
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parent.parent / "scripts" / "tldr_contained_runtime.py"
SPEC = importlib.util.spec_from_file_location("tldr_contained_runtime", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
runtime = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runtime)


class _FakeRelevantContext:
    def to_llm_string(self) -> str:
        return "serialized context"


class _FallbackObject:
    def __str__(self) -> str:
        return "fallback object"


def test_coerce_daemon_response_uses_llm_string_when_available():
    value = _FakeRelevantContext()

    assert runtime._coerce_daemon_response_value(value) == "serialized context"


def test_coerce_daemon_response_preserves_json_values():
    value = {"status": "ok", "items": [1, 2, 3]}

    assert runtime._coerce_daemon_response_value(value) == value


def test_coerce_daemon_response_falls_back_to_str_for_non_json_object():
    value = _FallbackObject()

    assert runtime._coerce_daemon_response_value(value) == "fallback object"


def test_coerce_daemon_response_recurses_through_dicts_and_lists():
    value = {
        "status": "ok",
        "result": {
            "items": [_FakeRelevantContext(), _FallbackObject()],
        },
    }

    assert runtime._coerce_daemon_response_value(value) == {
        "status": "ok",
        "result": {"items": ["serialized context", "fallback object"]},
    }


def _install_fake_tldr_modules(monkeypatch, *, send_command):
    semantic_mod = types.ModuleType("tldr.semantic")
    semantic_mod.semantic_search = lambda *args, **kwargs: {"semantic": "ok"}
    semantic_mod.build_semantic_index = lambda *args, **kwargs: None

    mcp_mod = types.ModuleType("tldr.mcp_server")
    mcp_mod._send_command = send_command
    mcp_mod._ping_daemon = lambda project: True
    mcp_mod._get_socket_path = lambda project: Path("/tmp/fake-tldr.sock")
    mcp_mod._get_lock_path = lambda project: Path("/tmp/fake-tldr.lock")
    mcp_mod._get_connection_info = lambda project: ("/tmp/fake-tldr.sock", None)

    tldr_pkg = types.ModuleType("tldr")
    tldr_pkg.semantic = semantic_mod
    tldr_pkg.mcp_server = mcp_mod

    monkeypatch.setitem(sys.modules, "tldr", tldr_pkg)
    monkeypatch.setitem(sys.modules, "tldr.semantic", semantic_mod)
    monkeypatch.setitem(sys.modules, "tldr.mcp_server", mcp_mod)
    return mcp_mod


def test_non_semantic_send_command_retries_json_decode_then_succeeds(monkeypatch):
    attempts = {"count": 0}

    def _flaky_send(project, command):
        attempts["count"] += 1
        if attempts["count"] == 1:
            raise json.JSONDecodeError("Expecting value", "", 0)
        return {"status": "ok"}

    mcp_mod = _install_fake_tldr_modules(monkeypatch, send_command=_flaky_send)
    monkeypatch.setattr(runtime.time, "sleep", lambda _seconds: None)

    runtime._patch_semantic_autobootstrap()
    result = mcp_mod._send_command("/tmp/project", {"cmd": "context", "action": "lookup"})

    assert result == {"status": "ok"}
    assert attempts["count"] == 2


def test_non_semantic_send_command_decode_failure_reports_diagnostic(monkeypatch):
    attempts = {"count": 0}

    def _always_fails(project, command):
        attempts["count"] += 1
        raise json.JSONDecodeError("Expecting value", "", 0)

    mcp_mod = _install_fake_tldr_modules(monkeypatch, send_command=_always_fails)
    monkeypatch.setattr(runtime.time, "sleep", lambda _seconds: None)
    monkeypatch.setattr(
        runtime,
        "_probe_daemon_raw_response",
        lambda **kwargs: {"probe_status": "eof", "bytes_received": 0, "raw_preview": ""},
    )

    runtime._patch_semantic_autobootstrap()

    try:
        mcp_mod._send_command(
            "/tmp/project",
            {"cmd": "context", "action": "lookup", "entry": "run_manual_substrate_expansion"},
        )
        raise AssertionError("expected RuntimeError")
    except RuntimeError as exc:
        message = str(exc)
        assert "llm-tldr MCP daemon JSON parse failure" in message
        assert '"cmd": "context"' in message
        assert '"probe_status": "eof"' in message
    assert attempts["count"] == 3
