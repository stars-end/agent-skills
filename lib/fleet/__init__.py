"""
Fleet Dispatch - Unified dispatch library for OpenCode and Jules backends.

Usage:
    from lib.fleet import FleetDispatcher, DispatchResult

    dispatcher = FleetDispatcher()
    result = dispatcher.dispatch(
        beads_id="bd-xxx",
        prompt="Fix the bug",
        repo="prime-radiant-ai",
        mode="real"
    )

SSH Fanout (hardened):
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
