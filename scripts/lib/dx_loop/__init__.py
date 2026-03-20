"""
dx-loop - PR-aware orchestration surface over dx-runner substrate

Reuses Ralph concepts (baton, topological deps, checkpoint/resume) while replacing
the control plane with governed dx-runner dispatch and enforcing PR artifact contracts.

v1.1 fixes:
- P0: Active work no longer redispatched every cadence (scheduler)
- P1: Blocked notifications emit on FIRST occurrence (state_machine)
- P1: State persistence is symmetric and durable (beads_integration)

v1.3 MVP pillars:
- Pillar A: Stacked-PR bootstrap (dependency artifact collection + prompt injection)
- Pillar B: Human takeover / bypass / resume
- Pillar C: Phase-aware provider routing
"""

from .state_machine import LoopState, BlockerCode, LoopStateMachine, LoopStateTracker
from .baton import BatonPhase, BatonManager, ReviewVerdict, BatonState
from .blocker import BlockerClassifier, BlockerState, BlockerSeverity
from .pr_contract import PRContractEnforcer, PRArtifact
from .beads_integration import BeadsWaveManager, BeadsTask, WaveReadiness
from .notifications import NotificationManager, Notification
from .scheduler import DxLoopScheduler, SchedulerState
from .runner_adapter import RunnerAdapter, RunnerTaskState

__all__ = [
    "LoopState",
    "BlockerCode",
    "LoopStateMachine",
    "LoopStateTracker",
    "BatonPhase",
    "BatonManager",
    "ReviewVerdict",
    "BatonState",
    "BlockerClassifier",
    "BlockerState",
    "BlockerSeverity",
    "PRContractEnforcer",
    "PRArtifact",
    "BeadsWaveManager",
    "BeadsTask",
    "WaveReadiness",
    "NotificationManager",
    "Notification",
    "DxLoopScheduler",
    "SchedulerState",
    "RunnerAdapter",
    "RunnerTaskState",
]

__version__ = "1.3.0"
