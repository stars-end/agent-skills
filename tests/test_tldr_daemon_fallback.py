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
    fake_runtime = types.ModuleType("tldr_contained_runtime")

    def _fake_apply_containment_patches(*, include_mcp: bool) -> None:
        apply_calls.append(include_mcp)

    fake_runtime.apply_containment_patches = _fake_apply_containment_patches
    monkeypatch.setitem(sys.modules, "tldr_contained_runtime", fake_runtime)

    spec = importlib.util.spec_from_file_location("tldr_daemon_fallback", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, apply_calls


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
    module, _ = _load_module(monkeypatch)
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
    module, apply_calls = _load_module(monkeypatch)
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
    module, apply_calls = _load_module(monkeypatch)
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
