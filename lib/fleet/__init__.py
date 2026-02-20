"""
Fleet Dispatch - Unified dispatch library for OpenCode and Jules backends.

================================================================================
COMPATIBILITY LAYER (bd-xga8.14.8)
================================================================================

This module is a COMPATIBILITY LAYER for the deprecated dx-dispatch.py shim.

**For canonical dispatch, use dx-runner directly:**
    dx-runner start --provider opencode --beads bd-xxx --prompt-file /tmp/p.prompt

**Break-glass only:** Use dx-dispatch (shell shim) or dx-dispatch.py when
dx-runner direct dispatch is unavailable.

This library remains for:
  - SSH fanout utilities (lib.fleet.ssh_fanout)
  - OpenCode preflight (lib.fleet.opencode_preflight)
  - No-op detection (lib.fleet.noop_gate)

The FleetDispatcher class is DEPRECATED. Use dx-runner for all dispatch.

Archive target: T+72h after dx-runner migration validation (see docs/specs/).

================================================================================

Legacy Usage (deprecated):
    from lib.fleet import FleetDispatcher, DispatchResult

    dispatcher = FleetDispatcher()
    result = dispatcher.dispatch(
        beads_id="bd-xxx",
        prompt="Fix the bug",
        repo="prime-radiant-ai",
        mode="real"
    )

SSH Fanout (hardened - still valid):
    from lib.fleet import fanout_ssh, run_preflight_checks

    # Run preflight checks first
    preflight = run_preflight_checks("epyc6")
    if preflight.status == PreflightStatus.OK:
        result = fanout_ssh("epyc6", "make test")

OpenCode Preflight (capability probing):
    from lib.fleet import run_opencode_preflight, PreflightResult

    preflight = run_opencode_preflight("opencode/glm-5-free")
    if preflight.status == PreflightStatus.OK:
        model = preflight.selected_model

No-Op Execution Gate:
    from lib.fleet import NoOpExecutionGate, ExecutionStatus

    gate = NoOpExecutionGate("/tmp/agents/bd-xxx/repo")
    should_abort, reason = gate.should_abort()
"""

from .dispatcher import FleetDispatcher, DispatchResult
from .monitor import FleetMonitor
from .config import FleetConfig
from .state import FleetStateStore
from .ssh_fanout import (
    fanout_ssh,
    run_preflight_checks,
    get_host_mapping,
    PreflightStatus,
    PreflightResult,
    FanoutOutcome,
    FanoutResult,
    HostMapping,
    CANONICAL_HOST_MAPPINGS,
)
from .opencode_preflight import (
    run_preflight as run_opencode_preflight,
    PreflightStatus as OpenCodePreflightStatus,
    PreflightResult as OpenCodePreflightResult,
    write_permission_config,
    MODEL_FALLBACK_CHAIN,
)
from .noop_gate import (
    NoOpExecutionGate,
    ExecutionStatus,
    ExecutionGateResult,
    classify_execution_failure,
)

__all__ = [
    "FleetDispatcher",
    "FleetMonitor",
    "DispatchResult",
    "FleetConfig",
    "FleetStateStore",
    # SSH Fanout
    "fanout_ssh",
    "run_preflight_checks",
    "get_host_mapping",
    "PreflightStatus",
    "PreflightResult",
    "FanoutOutcome",
    "FanoutResult",
    "HostMapping",
    "CANONICAL_HOST_MAPPINGS",
    # OpenCode Preflight
    "run_opencode_preflight",
    "OpenCodePreflightStatus",
    "OpenCodePreflightResult",
    "write_permission_config",
    "MODEL_FALLBACK_CHAIN",
    # No-Op Gate
    "NoOpExecutionGate",
    "ExecutionStatus",
    "ExecutionGateResult",
    "classify_execution_failure",
]

__version__ = "0.3.0"
