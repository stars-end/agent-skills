#!/usr/bin/env python3
"""
test_nightly_dispatch_integration.py - Integration tests for nightly dispatch

Real CLI smoke tests that run actual dx-runner commands.
Run with: RUN_SMOKE=1 pytest test_nightly_dispatch_integration.py -v
"""

import os
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from nightly_dispatch import (
    NightlyDispatcher,
    NightlyDispatchConfig,
    PreflightResult,
    SlackAlerter,
)


@pytest.mark.integration
@pytest.mark.skipif(
    os.environ.get("CI") != "true" and os.environ.get("RUN_SMOKE") != "1",
    reason="Real CLI smoke test - requires dx-runner installed. Set RUN_SMOKE=1 to run locally.",
)
def test_dx_runner_preflight_smoke():
    """
    Real smoke test: verify dx-runner preflight actually works.

    This runs REAL dx-runner CLI commands, not mocked subprocess.
    Run with: RUN_SMOKE=1 pytest test_nightly_dispatch_integration.py -v
    """
    dispatcher = NightlyDispatcher()

    # Test preflight for each provider
    for provider in ["opencode", "cc-glm", "gemini"]:
        result = dispatcher.run_preflight(provider, "test-model")

        # Should have a valid result (available or not)
        assert result.provider == provider
        assert isinstance(result.available, bool)

        print(f"  {provider}: available={result.available}, error={result.error}")


@pytest.mark.integration
@pytest.mark.skipif(
    os.environ.get("CI") != "true" and os.environ.get("RUN_SMOKE") != "1",
    reason="Real CLI smoke test - requires dx-runner installed",
)
def test_dx_runner_workflow_smoke():
    """
    Test full dx-runner workflow: start, check, stop with real CLI.
    """
    dispatcher = NightlyDispatcher()
    beads_id = f"smoke-test-{uuid.uuid4().hex[:8]}"

    # Create temporary prompt file for testing
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
        f.write("Test prompt for smoke test")
        prompt_file = Path(f.name)

    try:
        # Run preflight first to find an available provider
        provider = None
        for p in ["cc-glm", "gemini", "opencode"]:
            result = dispatcher.run_preflight(p, "test-model")
            if result.available:
                provider = p
                break

        if not provider:
            pytest.skip("No providers available for testing")

        # Test start with --prompt-file and model
        success = dispatcher.dispatch_with_runner(
            beads_id, provider, "test-model", prompt_file
        )

        if success:
            # Test check on the session
            status = dispatcher.check_dispatch_status(beads_id)
            assert status in ["running", "stopped"]

            # Cleanup
            dispatcher.stop_dispatch(beads_id)
    finally:
        # Cleanup temp prompt file
        try:
            prompt_file.unlink()
        except OSError:
            pass


class TestDispatchLogicUnit:
    """Fast unit tests with mocked behavior - no real CLI calls."""

    def test_parse_claim_error_multipart_name(self):
        """Verify regex captures multi-word owner names."""
        dispatcher = NightlyDispatcher()

        test_cases = [
            ("already claimed by Recovery Agent", "Recovery Agent", None),
            (
                "already claimed by System Auto-Fixer at 2026-02-19T06:00:00",
                "System Auto-Fixer",
                "2026-02-19T06:00:00",
            ),
            ("already claimed by nightly_dispatch", "nightly_dispatch", None),
            (
                "Error: already claimed by Some Long Agent Name here",
                "Some Long Agent Name here",
                None,
            ),
            (
                "ALREADY CLAIMED BY Test User at 2026-02-19T12:00:00",
                "Test User",
                "2026-02-19T12:00:00",
            ),
        ]

        for stderr, expected_owner, expected_ts in test_cases:
            result = dispatcher.parse_claim_error(stderr)
            assert result is not None, f"Failed to parse: {stderr}"
            assert result["claimed_by"] == expected_owner, (
                f"Expected '{expected_owner}', got '{result['claimed_by']}' for: {stderr}"
            )
            if expected_ts:
                assert result["claimed_at"] == expected_ts, (
                    f"Expected timestamp '{expected_ts}', got '{result['claimed_at']}'"
                )

    def test_parse_claim_error_no_match(self):
        """Verify no match for non-claim errors."""
        dispatcher = NightlyDispatcher()

        test_cases = [
            "Some other error message",
            "Permission denied",
            "",
            "claimed by",  # Missing 'already'
        ]

        for stderr in test_cases:
            result = dispatcher.parse_claim_error(stderr)
            assert result is None, f"Should not match: {stderr}"

    def test_write_prompt_secure(self):
        """Verify secure prompt file creation."""
        dispatcher = NightlyDispatcher()
        beads_id = "test-beads-123"
        prompt = "Test prompt content"

        prompt_file = None
        try:
            prompt_file = dispatcher.write_prompt_secure(beads_id, prompt)

            # File should exist
            assert prompt_file.exists()

            # Content should match
            assert prompt_file.read_text() == prompt

            # Permissions should be 0o600 (owner read/write only)
            mode = prompt_file.stat().st_mode
            assert (mode & 0o777) == 0o600, f"Expected 0o600, got {oct(mode & 0o777)}"

            # Filename should contain sanitized beads_id (hyphens preserved)
            assert "ndisp_test-beads-123_" in prompt_file.name
        finally:
            if prompt_file:
                dispatcher.cleanup_prompt_file(prompt_file)
                assert not prompt_file.exists()

    def test_write_prompt_secure_sanitization(self):
        """Verify beads_id sanitization for safe filenames."""
        dispatcher = NightlyDispatcher()

        test_cases = [
            ("bd-123.456", "bd-123_456"),  # Dot replaced, hyphen preserved
            ("test/path", "test_path"),  # Slash replaced
            ("a" * 100, "a" * 50),  # Truncated to 50 chars
            ("normal-id_123", "normal-id_123"),  # Already safe
        ]

        for beads_id, expected_substring in test_cases:
            prompt_file = None
            try:
                prompt_file = dispatcher.write_prompt_secure(beads_id, "test")
                assert expected_substring in prompt_file.name
            finally:
                if prompt_file:
                    dispatcher.cleanup_prompt_file(prompt_file)

    def test_config_migration_timeline(self):
        """Verify config migration timeline logic."""
        import tempfile

        with tempfile.TemporaryDirectory() as tmpdir:
            migration_file = Path(tmpdir) / "migration-start"

            # Create config with fresh migration file
            config = NightlyDispatchConfig()
            config._migration_start_file = migration_file
            # Write recent timestamp
            migration_file.write_text(datetime.now(timezone.utc).isoformat())

            # Initially should be in migration mode (MAX_PARALLEL=1)
            assert config.get_max_parallel() == 1
            assert not config.should_restore_parallelism()

            # Simulate 48h passing by modifying the migration file
            past_time = (datetime.now(timezone.utc) - timedelta(hours=49)).isoformat()
            migration_file.write_text(past_time)

            # Now should restore to MAX_PARALLEL=2
            assert config.should_restore_parallelism()
            assert config.get_max_parallel() == 2

    def test_deduplicate_bugs(self):
        """Verify bug deduplication logic."""
        dispatcher = NightlyDispatcher()

        bugs = [
            {"id": "bd-1", "title": "Same bug", "description": "Description A"},
            {
                "id": "bd-2",
                "title": "Same bug",
                "description": "Description A",
            },  # Duplicate
            {"id": "bd-3", "title": "Different bug", "description": "Description B"},
            {
                "id": "bd-4",
                "title": "Same bug",
                "description": "Description A different",
            },  # Different
        ]

        unique = dispatcher.deduplicate_bugs(bugs)

        # Should have 3 unique bugs (bd-2 is duplicate of bd-1)
        assert len(unique) == 3
        ids = [b["id"] for b in unique]
        assert "bd-1" in ids
        assert "bd-2" not in ids  # Duplicate removed
        assert "bd-3" in ids
        assert "bd-4" in ids


class TestSlackAlerter:
    """Test Slack alerter functionality."""

    def test_rate_limiting(self):
        """Verify alert rate limiting."""
        alerter = SlackAlerter(webhook_url="https://hooks.slack.com/test")
        alerter._rate_limit_minutes = 1  # Short limit for testing

        # First alert should be sent
        assert alerter._should_send_alert("test_alert")
        alerter._last_alert_time["test_alert"] = datetime.now(timezone.utc)

        # Second alert immediately should be rate limited
        assert not alerter._should_send_alert("test_alert")

        # Different alert type should not be rate limited
        assert alerter._should_send_alert("different_alert")

    def test_no_webhook(self):
        """Verify graceful handling when no webhook configured."""
        alerter = SlackAlerter(webhook_url=None)

        # Should not crash, just return False
        result = alerter.alert_fallback("opencode", "cc-glm", "test reason")
        assert result is False


class TestProviderSelection:
    """Test provider selection logic with mocked preflight."""

    def test_primary_provider_selection(self):
        """Test selecting primary provider when available."""
        dispatcher = NightlyDispatcher()

        # Mock preflight to return opencode available
        def mock_preflight(provider, model):
            if provider == "opencode":
                return PreflightResult(provider, True, model_checked=model)
            return PreflightResult(provider, False, error="Not needed")

        dispatcher.run_preflight = mock_preflight

        provider, model, results = dispatcher.select_provider()

        assert provider == "opencode"
        assert model == "zhipuai-coding-plan/glm-5"
        assert results["opencode"].available is True

    def test_fallback_to_cc_glm(self):
        """Test fallback when opencode unavailable."""
        dispatcher = NightlyDispatcher()

        # Mock preflight: opencode fails, cc-glm succeeds
        def mock_preflight(provider, model):
            if provider == "opencode":
                return PreflightResult(
                    provider, False, error="Rate limited", model_checked=model
                )
            elif provider == "cc-glm":
                return PreflightResult(provider, True, model_checked=model)
            return PreflightResult(provider, False, error="Not needed")

        dispatcher.run_preflight = mock_preflight
        dispatcher.alerter = SlackAlerter(webhook_url=None)  # Disable alerts

        provider, model, results = dispatcher.select_provider()

        assert provider == "cc-glm"
        assert results["opencode"].error == "Rate limited"

    def test_fallback_to_gemini(self):
        """Test fallback to gemini when both opencode and cc-glm fail."""
        dispatcher = NightlyDispatcher()

        def mock_preflight(provider, model):
            if provider == "opencode":
                return PreflightResult(provider, False, error="Rate limited")
            elif provider == "cc-glm":
                return PreflightResult(provider, False, error="No capacity")
            elif provider == "gemini":
                return PreflightResult(provider, True)
            return PreflightResult(provider, False, error="Unknown")

        dispatcher.run_preflight = mock_preflight
        dispatcher.alerter = SlackAlerter(webhook_url=None)

        provider, model, results = dispatcher.select_provider()

        assert provider == "gemini"
        assert results["cc-glm"].error == "No capacity"

    def test_no_providers_available(self):
        """Test error when no providers available."""
        dispatcher = NightlyDispatcher()

        def mock_preflight(provider, model):
            return PreflightResult(provider, False, error=f"{provider} down")

        dispatcher.run_preflight = mock_preflight
        dispatcher.alerter = SlackAlerter(webhook_url=None)

        with pytest.raises(RuntimeError) as exc_info:
            dispatcher.select_provider()

        assert "No providers available" in str(exc_info.value)


if __name__ == "__main__":
    # Run unit tests by default
    pytest.main([__file__, "-v", "-m", "not integration"])
