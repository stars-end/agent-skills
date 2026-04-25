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


def _missing_semantic_index(*args, **kwargs):
    raise FileNotFoundError("Semantic index not found")


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


def test_semantic_bootstrap_fails_fast_without_mcp_autobuild(monkeypatch, tmp_path):
    monkeypatch.delenv(runtime.MCP_SEMANTIC_AUTOBUILD_ENV, raising=False)
    monkeypatch.setattr(
        runtime,
        "_semantic_index_files",
        lambda project: (
            Path(project) / ".tldr/cache/semantic/index.faiss",
            Path(project) / ".tldr/cache/semantic/metadata.json",
        ),
    )

    result = runtime._ensure_semantic_bootstrap(
        build_semantic_index=lambda *args, **kwargs: 1,
        semantic_search=_missing_semantic_index,
        project_path=str(tmp_path),
        query="where is auth bootstrapped?",
        k=10,
        expand_graph=False,
        model=None,
    )

    assert result["status"] == "error"
    assert result["reason_code"] == "semantic_index_missing"
    assert result["autobuild_override"] == "TLDR_MCP_SEMANTIC_AUTOBUILD=1"
    assert "tldr-contained.sh semantic index" in result["next_command"]


def test_semantic_bootstrap_autobuild_override_builds_index(monkeypatch, tmp_path):
    monkeypatch.setenv(runtime.MCP_SEMANTIC_AUTOBUILD_ENV, "1")
    calls = []

    def semantic_search(*args, **kwargs):
        search_calls = [call for call in calls if call[0].startswith("search")]
        if len(search_calls) < 2:
            calls.append(("search-missing", args, kwargs))
            raise FileNotFoundError("Semantic index not found")
        calls.append(("search-ok", args, kwargs))
        return {"status": "ok", "results": []}

    def build_semantic_index(*args, **kwargs):
        calls.append(("build", args, kwargs))
        return 1

    result = runtime._ensure_semantic_bootstrap(
        build_semantic_index=build_semantic_index,
        semantic_search=semantic_search,
        project_path=str(tmp_path),
        query="where is auth bootstrapped?",
        k=3,
        expand_graph=False,
        model=None,
    )

    assert result == {"status": "ok", "results": []}
    assert [call[0] for call in calls] == [
        "search-missing",
        "search-missing",
        "build",
        "search-ok",
    ]
