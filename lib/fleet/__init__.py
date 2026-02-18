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
]

__version__ = "0.2.0"
