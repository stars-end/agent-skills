"""Repository adapters for gskill."""
from extended.gskill.adapters.prime_radiant_ai import PRIME_RADIANT_ADAPTER, get_prime_radiant_tasks
from extended.gskill.adapters.affordabot import AFFORDABOT_ADAPTER, get_affordabot_tasks

__all__ = [
    "PRIME_RADIANT_ADAPTER",
    "get_prime_radiant_tasks",
    "AFFORDABOT_ADAPTER",
    "get_affordabot_tasks",
]
