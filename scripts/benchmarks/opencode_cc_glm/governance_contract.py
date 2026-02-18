#!/usr/bin/env python3
"""Provider-agnostic governance contract for benchmark/orchestration runs."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Protocol


FailureCategory = Literal["harness", "model", "env"]


@dataclass(frozen=True)
class JobSpec:
    run_id: str
    workflow_id: str
    model: str
    prompt_id: str
    prompt_category: str
    prompt_title: str
    prompt_text: str


@dataclass(frozen=True)
class AttemptResult:
    success: bool
    return_code: int | None
    timed_out: bool
    startup_latency_ms: int | None
    first_output_latency_ms: int | None
    completion_latency_ms: int | None
    stdout: str
    stderr: str
    failure_category: FailureCategory | None
    failure_reason: str | None
    hint_match_ratio: float
    session_id: str | None
    used_model_fallback: bool


@dataclass(frozen=True)
class GateResult:
    passed: bool
    reason_code: str
    details: str


class ProviderAdapter(Protocol):
    """Stable adapter interface used by the governance runner."""

    def run_attempt(self, spec: JobSpec) -> AttemptResult:
        ...
