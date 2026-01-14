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
"""

from .dispatcher import FleetDispatcher, DispatchResult
from .monitor import FleetMonitor
from .config import FleetConfig
from .state import FleetStateStore

__all__ = [
    "FleetDispatcher",
    "FleetMonitor",
    "DispatchResult",
    "FleetConfig",
    "FleetStateStore",
]

__version__ = "0.1.0"
