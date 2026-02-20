#!/usr/bin/env python3
"""Unit tests for multi-provider soak validation runner.

Tests cover:
- JobSpec/JobResult data structures
- Round aggregation logic
- Provider summary computation
- Pass/fail gate logic
- Markdown report generation
"""

from __future__ import annotations

import json
import pathlib
import sys
import unittest
from dataclasses import asdict

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / "validation"))

from multi_provider_soak import (
    JobSpec,
    JobResult,
    RoundResult,
    SoakResult,
    compute_provider_summary,
    generate_markdown_report,
    get_provider_model,
    PROVIDERS,
    JOBS_PER_PROVIDER,
    OPENCODE_CANONICAL_MODEL,
)


class TestJobSpec(unittest.TestCase):
    def test_job_spec_creation(self) -> None:
        spec = JobSpec(
            beads_id="test-123",
            provider="opencode",
            prompt_id="echo_ok",
            prompt="Return OK",
            success_hint="OK",
            model="zhipuai-coding-plan/glm-5",
            worktree=pathlib.Path("/tmp/test"),
            round_num=1,
            job_index=0,
        )
        self.assertEqual(spec.beads_id, "test-123")
        self.assertEqual(spec.provider, "opencode")
        self.assertEqual(spec.model, "zhipuai-coding-plan/glm-5")

    def test_job_spec_to_dict(self) -> None:
        spec = JobSpec(
            beads_id="test-456",
            provider="cc-glm",
            prompt_id="echo_ready",
            prompt="Return READY",
            success_hint="READY",
            model="glm-5",
            worktree=pathlib.Path("/tmp/test2"),
            round_num=2,
            job_index=5,
        )
        d = asdict(spec)
        self.assertEqual(d["beads_id"], "test-456")
        self.assertEqual(d["worktree"], pathlib.Path("/tmp/test2"))


class TestJobResult(unittest.TestCase):
    def test_job_result_success(self) -> None:
        spec = JobSpec(
            beads_id="job-1",
            provider="opencode",
            prompt_id="echo_ok",
            prompt="Return OK",
            success_hint="OK",
            model="zhipuai-coding-plan/glm-5",
            worktree=pathlib.Path("/tmp"),
            round_num=1,
            job_index=0,
        )
        result = JobResult(
            job_spec=spec,
            success=True,
            status="exited_ok",
            reason_code=None,
            selected_model="zhipuai-coding-plan/glm-5",
            latency_ms=1500,
            completion=True,
            retries=0,
            outcome_state="success",
            stdout="OK",
            stderr="",
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:02Z",
        )
        self.assertTrue(result.success)
        self.assertEqual(result.latency_ms, 1500)

    def test_job_result_failure(self) -> None:
        spec = JobSpec(
            beads_id="job-2",
            provider="gemini",
            prompt_id="echo_ready",
            prompt="Return READY",
            success_hint="READY",
            model="gemini-3-flash-preview",
            worktree=pathlib.Path("/tmp"),
            round_num=1,
            job_index=1,
        )
        result = JobResult(
            job_spec=spec,
            success=False,
            status="exited_err",
            reason_code="model_unavailable",
            selected_model="gemini-3-flash-preview",
            latency_ms=500,
            completion=True,
            retries=1,
            outcome_state="failed",
            stdout="",
            stderr="Model not found",
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:01Z",
        )
        self.assertFalse(result.success)
        self.assertEqual(result.reason_code, "model_unavailable")

    def test_job_result_to_dict(self) -> None:
        spec = JobSpec(
            beads_id="job-3",
            provider="cc-glm",
            prompt_id="echo_ok",
            prompt="Return OK",
            success_hint="OK",
            model="glm-5",
            worktree=pathlib.Path("/tmp"),
            round_num=1,
            job_index=2,
        )
        result = JobResult(
            job_spec=spec,
            success=True,
            status="exited_ok",
            reason_code=None,
            selected_model="glm-5",
            latency_ms=1000,
            completion=True,
            retries=0,
            outcome_state="success",
            stdout="OK",
            stderr="",
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:01Z",
        )
        d = result.to_dict()
        self.assertIn("job_spec", d)
        self.assertEqual(d["job_spec"]["beads_id"], "job-3")


class TestRoundResult(unittest.TestCase):
    def _make_job(self, beads_id: str, success: bool) -> JobResult:
        spec = JobSpec(
            beads_id=beads_id,
            provider="opencode",
            prompt_id="echo_ok",
            prompt="Return OK",
            success_hint="OK",
            model="zhipuai-coding-plan/glm-5",
            worktree=pathlib.Path("/tmp"),
            round_num=1,
            job_index=0,
        )
        return JobResult(
            job_spec=spec,
            success=success,
            status="exited_ok" if success else "exited_err",
            reason_code=None if success else "failed",
            selected_model="zhipuai-coding-plan/glm-5",
            latency_ms=1000,
            completion=True,
            retries=0,
            outcome_state="success" if success else "failed",
            stdout="OK" if success else "",
            stderr="" if success else "error",
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:01Z",
        )

    def test_round_result_all_passed(self) -> None:
        jobs = [self._make_job(f"job-{i}", True) for i in range(6)]
        round_result = RoundResult(
            round_num=1,
            jobs=jobs,
            passed=True,
            pass_rate=1.0,
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:10Z",
            duration_sec=10.0,
        )
        self.assertTrue(round_result.passed)
        self.assertEqual(round_result.pass_rate, 1.0)

    def test_round_result_partial_failure(self) -> None:
        jobs = [self._make_job(f"job-{i}", i < 4) for i in range(6)]
        round_result = RoundResult(
            round_num=1,
            jobs=jobs,
            passed=False,
            pass_rate=4 / 6,
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:10Z",
            duration_sec=10.0,
        )
        self.assertFalse(round_result.passed)
        self.assertAlmostEqual(round_result.pass_rate, 0.667, places=2)


class TestProviderSummary(unittest.TestCase):
    def _make_round(self, provider_results: list[tuple[str, bool, int | None]]) -> RoundResult:
        jobs = []
        for i, (provider, success, latency) in enumerate(provider_results):
            spec = JobSpec(
                beads_id=f"job-{i}",
                provider=provider,
                prompt_id="echo_ok",
                prompt="Return OK",
                success_hint="OK",
                model=get_provider_model(provider),
                worktree=pathlib.Path("/tmp"),
                round_num=1,
                job_index=i,
            )
            jobs.append(JobResult(
                job_spec=spec,
                success=success,
                status="exited_ok" if success else "exited_err",
                reason_code=None if success else "failed",
                selected_model=spec.model,
                latency_ms=latency,
                completion=True,
                retries=0,
                outcome_state="success" if success else "failed",
                stdout="OK" if success else "",
                stderr="" if success else "error",
                started_at="2025-01-01T00:00:00Z",
                completed_at="2025-01-01T00:00:01Z",
            ))
        return RoundResult(
            round_num=1,
            jobs=jobs,
            passed=all(j.success for j in jobs),
            pass_rate=sum(1 for j in jobs if j.success) / len(jobs) if jobs else 0,
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:10Z",
            duration_sec=10.0,
        )

    def test_compute_provider_summary_all_success(self) -> None:
        provider_results = [
            ("opencode", True, 1000),
            ("opencode", True, 1200),
            ("cc-glm", True, 800),
            ("cc-glm", True, 900),
            ("gemini", True, 1500),
            ("gemini", True, 1600),
        ]
        round_result = self._make_round(provider_results)
        summary = compute_provider_summary([round_result])
        
        self.assertEqual(summary["opencode"]["total"], 2)
        self.assertEqual(summary["opencode"]["passed"], 2)
        self.assertEqual(summary["opencode"]["failed"], 0)
        self.assertEqual(summary["cc-glm"]["total"], 2)
        self.assertEqual(summary["gemini"]["total"], 2)

    def test_compute_provider_summary_mixed(self) -> None:
        provider_results = [
            ("opencode", True, 1000),
            ("opencode", False, None),
            ("cc-glm", True, 800),
            ("cc-glm", True, 900),
            ("gemini", False, 500),
            ("gemini", False, None),
        ]
        round_result = self._make_round(provider_results)
        summary = compute_provider_summary([round_result])
        
        self.assertEqual(summary["opencode"]["passed"], 1)
        self.assertEqual(summary["opencode"]["failed"], 1)
        self.assertEqual(summary["cc-glm"]["passed"], 2)
        self.assertEqual(summary["gemini"]["failed"], 2)

    def test_compute_provider_summary_latency_stats(self) -> None:
        provider_results = [
            ("opencode", True, 1000),
            ("opencode", True, 2000),
            ("opencode", True, 3000),
        ]
        round_result = self._make_round(provider_results)
        summary = compute_provider_summary([round_result])
        
        self.assertEqual(summary["opencode"]["latency_ms_mean"], 2000.0)
        self.assertEqual(summary["opencode"]["latency_ms_p50"], 2000)


class TestSoakResult(unittest.TestCase):
    def test_soak_result_all_clean(self) -> None:
        spec = JobSpec(
            beads_id="job-1",
            provider="opencode",
            prompt_id="echo_ok",
            prompt="Return OK",
            success_hint="OK",
            model="zhipuai-coding-plan/glm-5",
            worktree=pathlib.Path("/tmp"),
            round_num=1,
            job_index=0,
        )
        job = JobResult(
            job_spec=spec,
            success=True,
            status="exited_ok",
            reason_code=None,
            selected_model="zhipuai-coding-plan/glm-5",
            latency_ms=1000,
            completion=True,
            retries=0,
            outcome_state="success",
            stdout="OK",
            stderr="",
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:01Z",
        )
        round_result = RoundResult(
            round_num=1,
            jobs=[job],
            passed=True,
            pass_rate=1.0,
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:10Z",
            duration_sec=10.0,
        )
        
        soak = SoakResult(
            run_id="test-run",
            rounds=[round_result],
            passed=True,
            all_clean=True,
            total_jobs=1,
            total_passed=1,
            total_failed=0,
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:10Z",
            duration_sec=10.0,
            provider_summary={"opencode": {"total": 1, "passed": 1, "failed": 0, "latency_ms_mean": 1000, "latency_ms_p50": 1000}},
        )
        
        self.assertTrue(soak.passed)
        self.assertTrue(soak.all_clean)

    def test_soak_result_to_dict(self) -> None:
        spec = JobSpec(
            beads_id="job-1",
            provider="opencode",
            prompt_id="echo_ok",
            prompt="Return OK",
            success_hint="OK",
            model="zhipuai-coding-plan/glm-5",
            worktree=pathlib.Path("/tmp"),
            round_num=1,
            job_index=0,
        )
        job = JobResult(
            job_spec=spec,
            success=True,
            status="exited_ok",
            reason_code=None,
            selected_model="zhipuai-coding-plan/glm-5",
            latency_ms=1000,
            completion=True,
            retries=0,
            outcome_state="success",
            stdout="OK",
            stderr="",
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:01Z",
        )
        round_result = RoundResult(
            round_num=1,
            jobs=[job],
            passed=True,
            pass_rate=1.0,
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:10Z",
            duration_sec=10.0,
        )
        soak = SoakResult(
            run_id="test-run",
            rounds=[round_result],
            passed=True,
            all_clean=True,
            total_jobs=1,
            total_passed=1,
            total_failed=0,
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:10Z",
            duration_sec=10.0,
            provider_summary={"opencode": {"total": 1, "passed": 1, "failed": 0, "latency_ms_mean": 1000, "latency_ms_p50": 1000}},
        )
        
        d = soak.to_dict()
        self.assertIn("run_id", d)
        self.assertIn("rounds", d)
        self.assertIn("provider_summary", d)
        
        json_str = json.dumps(d, default=str)
        self.assertIn("test-run", json_str)


class TestMarkdownReport(unittest.TestCase):
    def test_generate_markdown_report_passed(self) -> None:
        spec = JobSpec(
            beads_id="job-1",
            provider="opencode",
            prompt_id="echo_ok",
            prompt="Return OK",
            success_hint="OK",
            model="zhipuai-coding-plan/glm-5",
            worktree=pathlib.Path("/tmp"),
            round_num=1,
            job_index=0,
        )
        job = JobResult(
            job_spec=spec,
            success=True,
            status="exited_ok",
            reason_code=None,
            selected_model="zhipuai-coding-plan/glm-5",
            latency_ms=1000,
            completion=True,
            retries=0,
            outcome_state="success",
            stdout="OK",
            stderr="",
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:01Z",
        )
        round_result = RoundResult(
            round_num=1,
            jobs=[job],
            passed=True,
            pass_rate=1.0,
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:10Z",
            duration_sec=10.0,
        )
        soak = SoakResult(
            run_id="test-run-passed",
            rounds=[round_result, round_result],
            passed=True,
            all_clean=True,
            total_jobs=2,
            total_passed=2,
            total_failed=0,
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:20Z",
            duration_sec=20.0,
            provider_summary={"opencode": {"total": 2, "passed": 2, "failed": 0, "latency_ms_mean": 1000, "latency_ms_p50": 1000}},
        )
        
        md = generate_markdown_report(soak)
        
        self.assertIn("PASSED", md)
        self.assertIn("test-run-passed", md)
        self.assertIn("All Clean", md)
        self.assertIn("opencode", md)
        self.assertIn("Round 1", md)
        self.assertIn("1000", md)

    def test_generate_markdown_report_failed(self) -> None:
        spec = JobSpec(
            beads_id="job-1",
            provider="gemini",
            prompt_id="echo_ok",
            prompt="Return OK",
            success_hint="OK",
            model="gemini-3-flash-preview",
            worktree=pathlib.Path("/tmp"),
            round_num=1,
            job_index=0,
        )
        job = JobResult(
            job_spec=spec,
            success=False,
            status="exited_err",
            reason_code="model_unavailable",
            selected_model="gemini-3-flash-preview",
            latency_ms=500,
            completion=True,
            retries=1,
            outcome_state="failed",
            stdout="",
            stderr="Model not available",
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:01Z",
        )
        round_result = RoundResult(
            round_num=1,
            jobs=[job],
            passed=False,
            pass_rate=0.0,
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:10Z",
            duration_sec=10.0,
        )
        soak = SoakResult(
            run_id="test-run-failed",
            rounds=[round_result],
            passed=False,
            all_clean=False,
            total_jobs=1,
            total_passed=0,
            total_failed=1,
            started_at="2025-01-01T00:00:00Z",
            completed_at="2025-01-01T00:00:10Z",
            duration_sec=10.0,
            provider_summary={"gemini": {"total": 1, "passed": 0, "failed": 1, "latency_ms_mean": 500, "latency_ms_p50": 500}},
        )
        
        md = generate_markdown_report(soak)
        
        self.assertIn("FAILED", md)
        self.assertIn("model_unavailable", md)


class TestProviderModel(unittest.TestCase):
    def test_get_provider_model_opencode(self) -> None:
        model = get_provider_model("opencode")
        self.assertEqual(model, OPENCODE_CANONICAL_MODEL)

    def test_get_provider_model_cc_glm(self) -> None:
        model = get_provider_model("cc-glm")
        self.assertEqual(model, "glm-5")

    def test_get_provider_model_gemini(self) -> None:
        model = get_provider_model("gemini")
        self.assertEqual(model, "gemini-3-flash-preview")

    def test_get_provider_model_unknown(self) -> None:
        model = get_provider_model("unknown")
        self.assertEqual(model, "unknown")


class TestConstants(unittest.TestCase):
    def test_providers_defined(self) -> None:
        self.assertEqual(PROVIDERS, ["opencode", "cc-glm", "gemini"])

    def test_jobs_per_provider(self) -> None:
        self.assertEqual(JOBS_PER_PROVIDER, 2)

    def test_opencode_canonical_model(self) -> None:
        self.assertEqual(OPENCODE_CANONICAL_MODEL, "zhipuai-coding-plan/glm-5")


if __name__ == "__main__":
    unittest.main(verbosity=2)
