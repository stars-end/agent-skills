"""
dx-loop - PR-aware orchestration surface over dx-runner substrate

Reuses Ralph concepts (baton, topological deps, checkpoint/resume) while replacing
the control plane with governed dx-runner dispatch and enforcing PR artifact contracts.
"""

from .state_machine import LoopState, BlockerCode
from .baton import BatonPhase, BatonManager
from .blocker import BlockerClassifier, BlockerState
from .pr_contract import PRContractEnforcer, PRArtifact
from .beads_integration import BeadsWaveManager
from .notifications import NotificationManager

__all__ = [
    "LoopState",
    "BlockerCode",
    "BatonPhase",
    "BatonManager",
    "BlockerClassifier",
    "BlockerState",
    "PRContractEnforcer",
    "PRArtifact",
    "BeadsWaveManager",
    "NotificationManager",
]

__version__ = "1.0.0"
