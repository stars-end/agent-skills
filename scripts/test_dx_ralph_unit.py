#!/usr/bin/env python3
"""
Unit tests for scripts/dx-ralph.py (stubs only; no real Beads/OpenCode calls).

Run:
  python3 scripts/test_dx_ralph_unit.py
"""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


def load_dx_ralph():
    repo_root = Path(__file__).resolve().parent.parent
    target = repo_root / "scripts" / "dx-ralph.py"
    spec = importlib.util.spec_from_file_location("dx_ralph", target)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["dx_ralph"] = module
    spec.loader.exec_module(module)  # type: ignore[attr-defined]
    return module


DX = load_dx_ralph()


class FakeBeads:
    def __init__(self, issues: dict[str, dict]):
        self.issues = issues

    def show(self, issue_id: str):
        return self.issues.get(issue_id)


def epic(
    issue_id: str,
    *,
    status: str = "open",
    labels: list[str] | None = None,
    deps: list[str] | None = None,
    repo: str | None = None,
):
    return {
        "id": issue_id,
        "title": f"Epic {issue_id}",
        "description": f"Desc {issue_id}",
        "status": status,
        "issue_type": "epic",
        "labels": labels or [],
        "repo": repo,
        "dependencies": [{"issue_id": issue_id, "depends_on_id": d, "type": "blocks"} for d in (deps or [])],
    }


def task(issue_id: str, *, status: str = "open"):
    return {
        "id": issue_id,
        "title": f"Task {issue_id}",
        "status": status,
        "issue_type": "task",
        "labels": [],
        "dependencies": [],
    }


class DxRalphPlanTests(unittest.TestCase):
    def setUp(self):
        self._orig_bd_show = DX.bd_show

    def tearDown(self):
        DX.bd_show = self._orig_bd_show

    def test_repo_resolution_prefers_repo_field(self):
        fb = FakeBeads({"bd-a": epic("bd-a", labels=["ralph-ready"], repo="agent-skills")})
        DX.bd_show = fb.show
        nodes, plan, layers, errors = DX.compute_plan(["bd-a"], repo_map={})
        self.assertFalse(errors)
        self.assertEqual(nodes["bd-a"].repo, "agent-skills")
        self.assertEqual(plan["bd-a"].state, "runnable")
        self.assertEqual(layers, [["bd-a"]])

    def test_repo_resolution_label_fallback(self):
        fb = FakeBeads({"bd-a": epic("bd-a", labels=["ralph-ready", "repo:affordabot"])})
        DX.bd_show = fb.show
        nodes, plan, layers, errors = DX.compute_plan(["bd-a"], repo_map={})
        self.assertEqual(nodes["bd-a"].repo, "affordabot")
        self.assertEqual(plan["bd-a"].state, "runnable")

    def test_repo_resolution_repo_map_last_resort(self):
        fb = FakeBeads({"bd-a": epic("bd-a", labels=["ralph-ready"])})
        DX.bd_show = fb.show
        nodes, plan, layers, errors = DX.compute_plan(["bd-a"], repo_map={"bd-a": "llm-common"})
        self.assertEqual(nodes["bd-a"].repo, "llm-common")
        self.assertEqual(plan["bd-a"].state, "runnable")

    def test_missing_ralph_ready_is_skipped(self):
        fb = FakeBeads({"bd-a": epic("bd-a", labels=["repo:agent-skills"])})
        DX.bd_show = fb.show
        nodes, plan, layers, errors = DX.compute_plan(["bd-a"], repo_map={})
        self.assertEqual(plan["bd-a"].state, "skipped")
        self.assertIn("ralph-ready", plan["bd-a"].reason)
        self.assertEqual(layers, [])

    def test_dependency_chain_layers(self):
        fb = FakeBeads(
            {
                "bd-a": epic("bd-a", labels=["ralph-ready"], deps=["bd-b"], repo="agent-skills"),
                "bd-b": epic("bd-b", labels=["ralph-ready"], repo="agent-skills"),
            }
        )
        DX.bd_show = fb.show
        nodes, plan, layers, errors = DX.compute_plan(["bd-a"], repo_map={})
        self.assertEqual([plan["bd-b"].state, plan["bd-a"].state], ["runnable", "runnable"])
        self.assertEqual(layers, [["bd-b"], ["bd-a"]])

    def test_unmet_non_epic_dependency_blocks(self):
        fb = FakeBeads(
            {
                "bd-a": epic("bd-a", labels=["ralph-ready"], deps=["bd-t1"], repo="agent-skills"),
                "bd-t1": task("bd-t1", status="open"),
            }
        )
        DX.bd_show = fb.show
        nodes, plan, layers, errors = DX.compute_plan(["bd-a"], repo_map={})
        self.assertEqual(plan["bd-a"].state, "blocked")
        self.assertIn("unmet dependencies", plan["bd-a"].reason)
        self.assertEqual(layers, [])

    def test_cycle_is_blocked(self):
        fb = FakeBeads(
            {
                "bd-a": epic("bd-a", labels=["ralph-ready"], deps=["bd-b"], repo="agent-skills"),
                "bd-b": epic("bd-b", labels=["ralph-ready"], deps=["bd-a"], repo="agent-skills"),
            }
        )
        DX.bd_show = fb.show
        nodes, plan, layers, errors = DX.compute_plan(["bd-a"], repo_map={})
        self.assertEqual(plan["bd-a"].state, "blocked")
        self.assertEqual(plan["bd-b"].state, "blocked")
        self.assertEqual(layers, [])


class DxRalphSignalTests(unittest.TestCase):
    def test_parse_signals(self):
        sig, _ = DX.parse_reviewer_signal("✅ APPROVED: looks good")
        self.assertEqual(sig, "APPROVED")
        sig, _ = DX.parse_reviewer_signal("🔴 REVISION_REQUIRED: fix")
        self.assertEqual(sig, "REVISION_REQUIRED")
        sig, _ = DX.parse_reviewer_signal("no signal")
        self.assertEqual(sig, "UNKNOWN")


if __name__ == "__main__":
    unittest.main(verbosity=2)
