#!/usr/bin/env python3
"""OpenCode preflight and model governance module.

Deterministic preflight checks for OpenCode dispatch environments:
- opencode binary presence
- provider/model availability
- auth/provider health probe
- mise trust state
- node + pnpm presence

Model policy with host-aware fallbacks:
- preferred: zai-coding-plan/glm-5
- host-aware fallback map for epyc12: zai/glm-5 -> opencode/glm-5-free
- fail fast if neither exists

Outputs machine-readable JSON with:
- selected_model
- selection_reason
- fallback_reason (if used)
- reason_code
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import os
import platform
import shutil
import subprocess
import sys
from typing import Any


@dataclasses.dataclass(frozen=True)
class PreflightResult:
    passed: bool
    reason_code: str
    selected_model: str | None
    selection_reason: str
    fallback_reason: str | None
    host: str
    opencode_bin: str | None
    opencode_version: str | None
    available_models: list[str]
    mise_trusted: bool | None
    node_version: str | None
    pnpm_version: str | None
    auth_probe_ok: bool
    details: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return dataclasses.asdict(self)


HOST_FALLBACK_MAPS: dict[str, dict[str, str]] = {
    "epyc12": {
        "zai-coding-plan/glm-5": "zai/glm-5",
        "zai/glm-5": "opencode/glm-5-free",
    },
    "epyc6": {
        "zai-coding-plan/glm-5": "zai/glm-5",
        "zai/glm-5": "opencode/glm-5-free",
    },
}

PREFERRED_MODEL = "zai-coding-plan/glm-5"
FALLBACK_CHAIN = ["zai/glm-5", "opencode/glm-5-free"]


def run_cmd(
    cmd: list[str],
    *,
    timeout_sec: float = 30.0,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout_sec,
        check=check,
    )


def check_opencode_binary() -> tuple[str | None, str | None]:
    for candidate in ["opencode", "/home/linuxbrew/.linuxbrew/bin/opencode"]:
        path = shutil.which(candidate)
        if path:
            try:
                proc = run_cmd([path, "--version"], timeout_sec=5.0)
                if proc.returncode == 0:
                    version = (
                        proc.stdout.strip().split()[-1]
                        if proc.stdout.strip()
                        else "unknown"
                    )
                    return path, version
            except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
                pass
    return None, None


def check_opencode_models(opencode_bin: str) -> list[str]:
    try:
        proc = run_cmd([opencode_bin, "models"], timeout_sec=30.0)
        if proc.returncode != 0:
            return []
        models: list[str] = []
        for line in proc.stdout.strip().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("- "):
                model_id = line[2:].strip()
                if "/" in model_id:
                    models.append(model_id)
            elif "/" in line:
                parts = line.split()
                if parts and "/" in parts[0]:
                    models.append(parts[0])
        return sorted(set(models))
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return []


def check_mise_trust() -> bool | None:
    try:
        proc = run_cmd(["mise", "trust", "--show"], timeout_sec=5.0)
        if proc.returncode == 0:
            return "trusted" in proc.stdout.lower() or proc.stdout.strip() != ""
        return False
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None


def check_node_version() -> str | None:
    try:
        proc = run_cmd(["node", "--version"], timeout_sec=5.0)
        if proc.returncode == 0:
            return proc.stdout.strip().lstrip("v")
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass
    return None


def check_pnpm_version() -> str | None:
    try:
        proc = run_cmd(["pnpm", "--version"], timeout_sec=5.0)
        if proc.returncode == 0:
            return proc.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass
    return None


def probe_auth_health(opencode_bin: str, model: str) -> bool:
    try:
        proc = run_cmd(
            [opencode_bin, "run", "--model", model, "--format", "json", "echo ok"],
            timeout_sec=15.0,
        )
        if proc.returncode == 0 and "ok" in proc.stdout.lower():
            return True
        stderr_lower = proc.stderr.lower()
        if (
            "unauthorized" in stderr_lower
            or "forbidden" in stderr_lower
            or "api key" in stderr_lower
        ):
            return False
        return proc.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return False


def resolve_model(
    preferred: str,
    available: list[str],
    host: str,
) -> tuple[str, str, str | None]:
    fallback_map = HOST_FALLBACK_MAPS.get(host, {})
    chain = [preferred]
    seen = {preferred}
    current = preferred
    while current:
        if current in available:
            reason = "preferred" if current == preferred else "fallback"
            fallback = (
                None if current == preferred else f"preferred {preferred} not available"
            )
            return current, reason, fallback
        next_model = fallback_map.get(current)
        if next_model and next_model not in seen:
            chain.append(next_model)
            seen.add(next_model)
            current = next_model
        else:
            break
    for fallback_model in FALLBACK_CHAIN:
        if fallback_model not in seen and fallback_model in available:
            return fallback_model, "fallback", f"preferred {preferred} not available"
    return "", "unavailable", f"no available model in fallback chain: {chain}"


def run_preflight(
    preferred_model: str = PREFERRED_MODEL,
    host: str | None = None,
    json_output: bool = False,
) -> PreflightResult:
    host = host or platform.node().split(".")[0]
    details: dict[str, Any] = {}

    opencode_bin, opencode_version = check_opencode_binary()
    if not opencode_bin:
        result = PreflightResult(
            passed=False,
            reason_code="opencode_not_found",
            selected_model=None,
            selection_reason="opencode binary not found in PATH",
            fallback_reason=None,
            host=host,
            opencode_bin=None,
            opencode_version=None,
            available_models=[],
            mise_trusted=None,
            node_version=None,
            pnpm_version=None,
            auth_probe_ok=False,
            details=details,
        )
        if json_output:
            print(json.dumps(result.to_dict(), indent=2))
        return result

    available_models = check_opencode_models(opencode_bin)
    details["raw_models_output_count"] = len(available_models)

    selected_model, selection_reason, fallback_reason = resolve_model(
        preferred_model, available_models, host
    )

    if not selected_model:
        result = PreflightResult(
            passed=False,
            reason_code="model_unavailable",
            selected_model=None,
            selection_reason=selection_reason,
            fallback_reason=fallback_reason,
            host=host,
            opencode_bin=opencode_bin,
            opencode_version=opencode_version,
            available_models=available_models,
            mise_trusted=None,
            node_version=None,
            pnpm_version=None,
            auth_probe_ok=False,
            details=details,
        )
        if json_output:
            print(json.dumps(result.to_dict(), indent=2))
        return result

    mise_trusted = check_mise_trust()
    node_version = check_node_version()
    pnpm_version = check_pnpm_version()

    if mise_trusted is False:
        details["mise_warning"] = "mise trust --show returned untrusted"

    auth_probe_ok = probe_auth_health(opencode_bin, selected_model)
    if not auth_probe_ok:
        details["auth_probe_warning"] = (
            "auth probe did not return success (non-blocking)"
        )

    passed = bool(selected_model)

    reason_code = "preflight_ok" if passed else "model_unavailable"

    result = PreflightResult(
        passed=passed,
        reason_code=reason_code,
        selected_model=selected_model,
        selection_reason=selection_reason,
        fallback_reason=fallback_reason,
        host=host,
        opencode_bin=opencode_bin,
        opencode_version=opencode_version,
        available_models=available_models,
        mise_trusted=mise_trusted,
        node_version=node_version,
        pnpm_version=pnpm_version,
        auth_probe_ok=auth_probe_ok,
        details=details,
    )

    if json_output:
        print(json.dumps(result.to_dict(), indent=2))

    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="OpenCode preflight and model governance"
    )
    parser.add_argument(
        "--preferred-model",
        default=PREFERRED_MODEL,
        help="Preferred model in provider/model format",
    )
    parser.add_argument(
        "--host", default=None, help="Override hostname for fallback map"
    )
    parser.add_argument("--json", action="store_true", help="Output JSON to stdout")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = run_preflight(
        preferred_model=args.preferred_model,
        host=args.host,
        json_output=args.json,
    )
    return 0 if result.passed else 1


if __name__ == "__main__":
    sys.exit(main())
