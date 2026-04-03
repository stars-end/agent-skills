from __future__ import annotations

import importlib.util
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
