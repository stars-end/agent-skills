"""Tests for retry/fallback policy with hard caps."""
import pytest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import RetryPolicy, DEFAULT_RETRY_CHAIN, DEFAULT_MAX_ATTEMPTS


class TestRetryPolicy:
    """Test deterministic retry/fallback policy."""

    def test_fallback_order_exact(self):
        policy = RetryPolicy(retry_chain=["opencode", "cc-glm", "blocked"], max_attempts=3)

        p1, r1 = policy.get_provider_for_attempt(1)
        assert p1 == "opencode"
        assert r1 == "primary"

        p2, r2 = policy.get_provider_for_attempt(2, previous_provider="opencode")
        assert p2 == "cc-glm"
        assert "fallback" in r2

        p3, r3 = policy.get_provider_for_attempt(3, previous_provider="cc-glm")
        assert p3 == "blocked"

    def test_max_attempt_cap_enforced(self):
        policy = RetryPolicy(retry_chain=["opencode", "cc-glm", "blocked"], max_attempts=3)

        provider, reason = policy.get_provider_for_attempt(4)
        assert provider == "blocked"
        assert "exceeded" in reason.lower() or "exhausted" in reason.lower()

    def test_terminal_blocked_when_exhausted(self):
        policy = RetryPolicy(retry_chain=["opencode", "cc-glm"], max_attempts=5)

        assert policy.is_terminal("blocked")
        assert not policy.is_terminal("opencode")
        assert not policy.is_terminal("cc-glm")

    def test_should_retry_logic(self):
        policy = RetryPolicy(max_attempts=3)

        assert policy.should_retry(1)
        assert policy.should_retry(2)
        assert not policy.should_retry(3)
