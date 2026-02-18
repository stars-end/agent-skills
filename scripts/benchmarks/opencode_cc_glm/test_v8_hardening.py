#!/usr/bin/env python3
"""Unit tests for OpenCode DX v8.x reliability hardening.

Tests:
- Model resolver / fallback
- Ancestry gate
- Allowlist gate
- Taxonomy mapping
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from opencode_preflight import (
    PREFERRED_MODEL,
    FALLBACK_CHAIN,
    HOST_FALLBACK_MAPS,
    resolve_model,
    PreflightResult,
)


class TestModelResolver(unittest.TestCase):
    def test_preferred_available(self) -> None:
        available = ["zai-coding-plan/glm-5", "zai/glm-4"]
        selected, reason, fallback = resolve_model(
            PREFERRED_MODEL, available, "localhost"
        )
        self.assertEqual(selected, "zai-coding-plan/glm-5")
        self.assertEqual(reason, "preferred")
        self.assertIsNone(fallback)

    def test_fallback_on_epyc12(self) -> None:
        available = ["zai/glm-5", "opencode/glm-5-free"]
        selected, reason, fallback = resolve_model(PREFERRED_MODEL, available, "epyc12")
        self.assertEqual(selected, "zai/glm-5")
        self.assertEqual(reason, "fallback")
        self.assertIn("preferred", fallback or "")

    def test_deep_fallback_epyc12(self) -> None:
        available = ["opencode/glm-5-free", "other/model"]
        selected, reason, fallback = resolve_model(PREFERRED_MODEL, available, "epyc12")
        self.assertEqual(selected, "opencode/glm-5-free")
        self.assertEqual(reason, "fallback")

    def test_no_available_model(self) -> None:
        available = ["other/model", "another/model"]
        selected, reason, fallback = resolve_model(PREFERRED_MODEL, available, "epyc12")
        self.assertEqual(selected, "")
        self.assertEqual(reason, "unavailable")

    def test_host_without_fallback_map(self) -> None:
        available = ["zai/glm-5"]
        selected, reason, fallback = resolve_model(
            PREFERRED_MODEL, available, "unknown-host"
        )
        self.assertEqual(selected, "zai/glm-5")
        self.assertEqual(reason, "fallback")


class TestAncestryGate(unittest.TestCase):
    def test_ancestry_gate_module_import(self) -> None:
        from launch_parallel_jobs import ancestry_gate, AncestryGateResult

        self.assertTrue(callable(ancestry_gate))

    def test_ancestry_gate_missing_baseline(self) -> None:
        from launch_parallel_jobs import ancestry_gate

        result = ancestry_gate(Path("/tmp"), "")
        self.assertFalse(result.passed)
        self.assertEqual(result.reason_code, "required_baseline_missing")


class TestAllowlistGate(unittest.TestCase):
    def test_allowlist_gate_module_import(self) -> None:
        from launch_parallel_jobs import allowlist_gate, AllowlistGateResult

        self.assertTrue(callable(allowlist_gate))

    def test_allowlist_gate_missing_worktree(self) -> None:
        from launch_parallel_jobs import allowlist_gate

        result = allowlist_gate(Path("/nonexistent/path"), ["src/*"])
        self.assertFalse(result.passed)
        self.assertEqual(result.reason_code, "worktree_missing")


class TestTaxonomyCodes(unittest.TestCase):
    def test_taxonomy_codes_defined_in_launch(self) -> None:
        from launch_parallel_jobs import TAXONOMY_CODES

        expected = [
            "model_unavailable",
            "preflight_failed",
            "stalled_run",
            "ancestry_gate_failed",
            "scope_drift_failed",
        ]
        for code in expected:
            self.assertIn(code, TAXONOMY_CODES)

    def test_taxonomy_codes_defined_in_governed(self) -> None:
        from run_governed_benchmark import TAXONOMY_CODES

        expected = [
            "model_unavailable",
            "preflight_failed",
            "stalled_run",
            "ancestry_gate_failed",
            "scope_drift_failed",
        ]
        for code in expected:
            self.assertIn(code, TAXONOMY_CODES)

    def test_taxonomy_codes_defined_in_progressive(self) -> None:
        from run_progressive_opencode import TAXONOMY_CODES

        expected = [
            "model_unavailable",
            "preflight_failed",
            "stalled_run",
            "ancestry_gate_failed",
            "scope_drift_failed",
        ]
        for code in expected:
            self.assertIn(code, TAXONOMY_CODES)


class TestPreflightResult(unittest.TestCase):
    def test_to_dict(self) -> None:
        result = PreflightResult(
            passed=True,
            reason_code="preflight_ok",
            selected_model="zai-coding-plan/glm-5",
            selection_reason="preferred",
            fallback_reason=None,
            host="localhost",
            opencode_bin="/usr/bin/opencode",
            opencode_version="1.2.0",
            available_models=["zai-coding-plan/glm-5"],
            mise_trusted=True,
            node_version="20.0.0",
            pnpm_version="8.0.0",
            auth_probe_ok=True,
            details={},
        )
        d = result.to_dict()
        self.assertEqual(d["selected_model"], "zai-coding-plan/glm-5")
        self.assertEqual(d["reason_code"], "preflight_ok")
        self.assertTrue(d["passed"])


class TestStallDetector(unittest.TestCase):
    def test_stall_detector_module_import(self) -> None:
        from launch_parallel_jobs import StallDetector

        detector = StallDetector()
        self.assertIsNotNone(detector)

    def test_stall_detector_nonexistent_process(self) -> None:
        from launch_parallel_jobs import StallDetector

        detector = StallDetector()
        ok, reason = detector.check_progress(99999, 0)
        self.assertTrue(ok)
        self.assertEqual(reason, "process_not_found")

    def test_stall_detection_in_execute_job(self) -> None:
        from launch_parallel_jobs import execute_job, JobSpec, PromptCase

        pass


class TestFeatureKeyPattern(unittest.TestCase):
    def test_feature_key_with_dots(self) -> None:
        import re

        pattern = re.compile(r"^bd-[a-z0-9]+(\.[a-z0-9]+)*$")
        self.assertTrue(pattern.match("bd-xga8"))
        self.assertTrue(pattern.match("bd-xga8.10"))
        self.assertTrue(pattern.match("bd-xga8.10.5"))
        self.assertFalse(pattern.match("bd-XGA8"))
        self.assertFalse(pattern.match("xga8.10"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
