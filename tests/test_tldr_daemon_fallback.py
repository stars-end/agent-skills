from __future__ import annotations

import argparse
import importlib.util
import json
import sys
import types
from pathlib import Path


MODULE_PATH = (
    Path(__file__).resolve().parent.parent / "scripts" / "tldr-daemon-fallback.py"
)


def _load_module(monkeypatch):
    apply_calls: list[bool] = []
    index_ready = {"value": True}
    fake_runtime = types.ModuleType("tldr_contained_runtime")

    def _fake_apply_containment_patches(*, include_mcp: bool) -> None:
        apply_calls.append(include_mcp)

    def _fake_semantic_index_ready(project: str) -> bool:
        return index_ready["value"]

    def _fake_semantic_index_files(project: str):
        project_path = Path(project)
        return (
            project_path / ".tldr" / "cache" / "semantic" / "index.faiss",
            project_path / ".tldr" / "cache" / "semantic" / "metadata.json",
        )

    fake_runtime.apply_containment_patches = _fake_apply_containment_patches
    fake_runtime._semantic_index_ready = _fake_semantic_index_ready
    fake_runtime._semantic_index_files = _fake_semantic_index_files
    monkeypatch.setitem(sys.modules, "tldr_contained_runtime", fake_runtime)

    spec = importlib.util.spec_from_file_location("tldr_daemon_fallback", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, apply_calls, index_ready


def _install_fake_mcp(monkeypatch, result: dict):
    calls: list[tuple[str, dict]] = []
    fake_tldr = types.ModuleType("tldr")
    fake_mcp = types.ModuleType("tldr.mcp_server")

    def _make_tool(name: str):
        def _tool(**kwargs):
            calls.append((name, kwargs))
            return {"tool": name, **result}

        return _tool

    for tool_name in (
        "tree",
        "structure",
        "search",
        "extract",
        "context",
        "cfg",
        "dfg",
        "slice",
        "impact",
        "dead",
        "arch",
        "calls",
        "imports",
        "importers",
        "semantic",
        "diagnostics",
        "change_impact",
        "status",
    ):
        setattr(fake_mcp, tool_name, _make_tool(tool_name))

    fake_tldr.mcp_server = fake_mcp
    monkeypatch.setitem(sys.modules, "tldr", fake_tldr)
    monkeypatch.setitem(sys.modules, "tldr.mcp_server", fake_mcp)
    return calls


def _subparser_choices(parser: argparse.ArgumentParser) -> set[str]:
    for action in parser._actions:
        if isinstance(action, argparse._SubParsersAction):
            return set(action.choices.keys())
    raise AssertionError("subparser action missing")


def test_parser_includes_expanded_command_surface(monkeypatch):
    module, _, _ = _load_module(monkeypatch)
    parser = module._build_parser()
    commands = _subparser_choices(parser)

    assert {
        "tree",
        "structure",
        "search",
        "extract",
        "context",
        "cfg",
        "dfg",
        "slice",
        "impact",
        "dead",
        "arch",
        "calls",
        "imports",
        "importers",
        "semantic",
        "diagnostics",
        "change-impact",
        "change_impact",
        "status",
    }.issubset(commands)


def test_tree_uses_daemon_backed_mcp_path(monkeypatch, capsys, tmp_path):
    module, apply_calls, _ = _load_module(monkeypatch)
    calls = _install_fake_mcp(monkeypatch, result={"status": "ok"})

    exit_code = module.main(
        [
            "tree",
            "--repo",
            str(tmp_path),
            "--extension",
            ".py",
            "--extension",
            ".md",
        ]
    )
    output = capsys.readouterr().out

    assert exit_code == 0
    assert apply_calls == [True]
    assert calls == [
        (
            "tree",
            {
                "project": str(tmp_path.resolve()),
                "extensions": [".py", ".md"],
            },
        )
    ]
    assert json.loads(output)["tool"] == "tree"


def test_change_impact_alias_routes_to_mcp_tool(monkeypatch, capsys, tmp_path):
    module, apply_calls, _ = _load_module(monkeypatch)
    calls = _install_fake_mcp(monkeypatch, result={"status": "ok"})
    changed_file = tmp_path / "scripts" / "tldr-daemon-fallback.py"

    exit_code = module.main(
        [
            "change-impact",
            "--project",
            str(tmp_path),
            "--file",
            str(changed_file),
        ]
    )
    output = capsys.readouterr().out

    assert exit_code == 0
    assert apply_calls == [True]
    assert calls == [
        (
            "change_impact",
            {
                "project": str(tmp_path.resolve()),
                "files": [str(changed_file.resolve())],
            },
        )
    ]
    assert json.loads(output)["tool"] == "change_impact"


def test_semantic_missing_index_fails_fast_without_mcp_call(monkeypatch, capsys, tmp_path):
    module, apply_calls, index_ready = _load_module(monkeypatch)
    index_ready["value"] = False
    calls = _install_fake_mcp(monkeypatch, result={"status": "ok"})

    exit_code = module.main(
        [
            "semantic",
            "--repo",
            str(tmp_path),
            "--query",
            "where is bdx routing implemented?",
        ]
    )
    output = json.loads(capsys.readouterr().out)

    assert exit_code == 3
    assert apply_calls == [True]
    assert calls == []
    assert output["ok"] is False
    assert output["reason_code"] == "semantic_index_missing"
    assert "tldr-contained.sh semantic index" in output["next_command"]
    assert output["autobuild_override"] == "TLDR_FALLBACK_SEMANTIC_AUTOBUILD=1"


def test_semantic_autobuild_override_routes_to_mcp(monkeypatch, capsys, tmp_path):
    module, apply_calls, index_ready = _load_module(monkeypatch)
    index_ready["value"] = False
    calls = _install_fake_mcp(monkeypatch, result={"status": "ok"})
    monkeypatch.setenv("TLDR_FALLBACK_SEMANTIC_AUTOBUILD", "1")
    monkeypatch.delenv("TLDR_SEMANTIC_AUTOBUILD_MODEL", raising=False)

    exit_code = module.main(
        [
            "semantic",
            "--repo",
            str(tmp_path),
            "--query",
            "where is bdx routing implemented?",
            "--k",
            "3",
        ]
    )
    output = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert apply_calls == [True]
    assert calls == [
        (
            "semantic",
            {
                "project": str(tmp_path.resolve()),
                "query": "where is bdx routing implemented?",
                "k": 3,
            },
        )
    ]
    assert output["tool"] == "semantic"
    assert module.os.environ["TLDR_SEMANTIC_AUTOBUILD_MODEL"] == "all-MiniLM-L6-v2"
