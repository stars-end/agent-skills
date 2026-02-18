#!/usr/bin/env python
"""
OpenCode Preflight - Capability probing and validation before dispatch.

Addresses bd-cbsb.15: Strict capability preflight with fallback chain.
"""

from __future__ import annotations

import json
import subprocess
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any


class PreflightStatus(Enum):
    OK = "ok"
    MODEL_NOT_FOUND = "model_not_found"
    PROVIDER_AUTH_FAILED = "provider_auth_failed"
    QUOTA_EXCEEDED = "quota_exceeded"
    RATE_LIMITED = "rate_limited"
    PROVIDER_UNREACHABLE = "provider_unreachable"
    UNKNOWN_ERROR = "unknown_error"


@dataclass
class ModelProbeResult:
    model_id: str
    provider: str
    available: bool
    error: str | None = None


@dataclass
class PreflightResult:
    status: PreflightStatus
    preferred_model: str
    selected_model: str
    fallback_reason: str | None = None
    probe_results: list[ModelProbeResult] = field(default_factory=list)
    error_detail: str | None = None
    elapsed_ms: int = 0


MODEL_FALLBACK_CHAIN = [
    ("zhipuai-coding-plan/glm-5", "zhipuai-coding-plan"),
    ("opencode/glm-5-free", "opencode"),
    ("zhipu/glm-4-flash", "zhipu"),
]

WORKTREE_PERMISSION_RULES = [
    {"permission": "external_directory", "pattern": "/tmp/agents/*", "action": "allow"},
    {
        "permission": "external_directory",
        "pattern": "/home/*/agent-skills/*",
        "action": "allow",
    },
    {"permission": "external_directory", "pattern": "*", "action": "deny"},
    {"permission": "*", "pattern": "*", "action": "allow"},
    {"permission": "question", "pattern": "*", "action": "deny"},
    {"permission": "plan_enter", "pattern": "*", "action": "deny"},
    {"permission": "plan_exit", "pattern": "*", "action": "deny"},
]


def probe_opencode_models() -> list[dict[str, Any]]:
    """Probe opencode CLI for available models."""
    try:
        result = subprocess.run(
            ["opencode", "models", "--json"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            if isinstance(data, list):
                return data
            if isinstance(data, dict) and "models" in data:
                return data["models"]
        return []
    except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
        return []


def probe_model_availability(model_id: str, provider: str) -> ModelProbeResult:
    """Check if a specific model is available."""
    models = probe_opencode_models()

    for m in models:
        if isinstance(m, dict):
            mid = m.get("id", "") or m.get("model_id", "") or m.get("name", "")
            prov = m.get("provider", "") or m.get("provider_id", "")
            if mid == model_id or f"{prov}/{mid}" == model_id:
                return ModelProbeResult(
                    model_id=model_id,
                    provider=provider,
                    available=True,
                )

    return ModelProbeResult(
        model_id=model_id,
        provider=provider,
        available=False,
        error=f"Model {model_id} not found in provider {provider}",
    )


def test_model_auth(model_id: str, provider: str) -> tuple[bool, str | None]:
    """Test if model auth is working by making a minimal request."""
    try:
        result = subprocess.run(
            ["opencode", "run", "--model", model_id, "--dry-run", "test"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode == 0:
            return True, None

        stderr = result.stderr.lower()
        if "auth" in stderr or "unauthorized" in stderr or "api key" in stderr:
            return False, "PROVIDER_AUTH_FAILED"
        if "quota" in stderr or "rate limit" in stderr:
            return False, "QUOTA_EXCEEDED" if "quota" in stderr else "RATE_LIMITED"
        if "not found" in stderr or "unknown model" in stderr:
            return False, "MODEL_NOT_FOUND"
        return False, f"UNKNOWN_ERROR: {result.stderr[:200]}"
    except subprocess.TimeoutExpired:
        return False, "PROVIDER_TIMEOUT"
    except FileNotFoundError:
        return False, "OPENCODE_NOT_FOUND"


def run_preflight(
    preferred_model: str | None = None,
    fallback_chain: list[tuple[str, str]] | None = None,
) -> PreflightResult:
    """
    Run preflight checks for OpenCode dispatch.

    Returns PreflightResult with selected model or failure reason.
    """
    start_time = time.time()

    chain = fallback_chain or MODEL_FALLBACK_CHAIN
    probe_results: list[ModelProbeResult] = []

    if preferred_model:
        provider = (
            preferred_model.split("/")[0] if "/" in preferred_model else "opencode"
        )
        chain = [(preferred_model, provider)] + [
            m for m in chain if m[0] != preferred_model
        ]

    selected_model = None
    fallback_reason = None

    for model_id, provider in chain:
        probe = probe_model_availability(model_id, provider)
        probe_results.append(probe)

        if not probe.available:
            fallback_reason = fallback_reason or f"Model {model_id} not available"
            continue

        auth_ok, auth_error = test_model_auth(model_id, provider)
        if auth_ok:
            selected_model = model_id
            break

        fallback_reason = fallback_reason or f"{model_id}: {auth_error}"
        probe.error = auth_error

    elapsed_ms = int((time.time() - start_time) * 1000)

    if selected_model:
        status = PreflightStatus.OK
    elif any(p.error and "AUTH" in p.error for p in probe_results):
        status = PreflightStatus.PROVIDER_AUTH_FAILED
    elif any(p.error and "QUOTA" in p.error for p in probe_results):
        status = PreflightStatus.QUOTA_EXCEEDED
    elif all(not p.available for p in probe_results):
        status = PreflightStatus.MODEL_NOT_FOUND
    else:
        status = PreflightStatus.UNKNOWN_ERROR

    return PreflightResult(
        status=status,
        preferred_model=preferred_model or chain[0][0],
        selected_model=selected_model or "",
        fallback_reason=fallback_reason
        if selected_model != (preferred_model or chain[0][0])
        else None,
        probe_results=probe_results,
        elapsed_ms=elapsed_ms,
        error_detail=None if status == PreflightStatus.OK else fallback_reason,
    )


def generate_permission_config(worktree_path: str) -> dict:
    """
    Generate OpenCode permission config for headless execution.

    Addresses bd-cbsb.16: Worktree-only path policy.
    """
    rules = [
        {
            "permission": "external_directory",
            "pattern": f"{worktree_path}/*",
            "action": "allow",
        },
        {
            "permission": "external_directory",
            "pattern": "/home/*/.local/share/opencode/*",
            "action": "allow",
        },
        {"permission": "external_directory", "pattern": "*", "action": "deny"},
        {"permission": "*", "pattern": "*", "action": "allow"},
        {"permission": "question", "pattern": "*", "action": "deny"},
        {"permission": "plan_enter", "pattern": "*", "action": "deny"},
        {"permission": "plan_exit", "pattern": "*", "action": "deny"},
    ]
    return {"permissions": rules}


def write_permission_config(worktree_path: str, config_dir: Path | None = None) -> Path:
    """Write permission config to opencode.jsonc in the worktree."""
    if config_dir is None:
        config_dir = Path(worktree_path) / ".opencode"

    config_dir.mkdir(parents=True, exist_ok=True)
    config_path = config_dir / "opencode.jsonc"

    config = generate_permission_config(worktree_path)

    with open(config_path, "w") as f:
        f.write("// Auto-generated by opencode_preflight.py\n")
        f.write("// Worktree-only permission policy\n")
        json.dump(config, f, indent=2)

    return config_path


if __name__ == "__main__":
    import sys

    print("=== OpenCode Preflight Check ===\n")

    result = run_preflight()

    print(f"Status: {result.status.value}")
    print(f"Preferred: {result.preferred_model}")
    print(f"Selected: {result.selected_model or 'NONE'}")
    if result.fallback_reason:
        print(f"Fallback reason: {result.fallback_reason}")
    print(f"Elapsed: {result.elapsed_ms}ms")

    print("\nProbe results:")
    for p in result.probe_results:
        status = "✓" if p.available else "✗"
        print(f"  {status} {p.model_id} ({p.provider})")
        if p.error:
            print(f"      Error: {p.error}")

    if result.status != PreflightStatus.OK:
        sys.exit(1)
