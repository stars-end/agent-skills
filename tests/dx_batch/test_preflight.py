"""Tests for preflight gates before queue start."""
import shutil
import subprocess
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import PreflightChecker


class TestPreflight:
    """Test preflight gates."""

    def test_preflight_checks_all_providers_in_policy(self):
        checker = PreflightChecker(["opencode", "cc-glm", "gemini"])

        with patch.object(checker, '_check_provider') as mock_check:
            mock_check.side_effect = [
                {"provider": "opencode", "available": True},
                {"provider": "cc-glm", "available": True},
                {"provider": "gemini", "available": False, "error": "Not configured"},
            ]

            all_passed, results = checker.run()

            assert mock_check.call_count == 3
            assert "opencode" in results
            assert "cc-glm" in results
            assert "gemini" in results

    def test_preflight_summary_reason_codes(self):
        checker = PreflightChecker(["opencode", "cc-glm"])

        with patch.object(checker, '_check_provider') as mock_check:
            mock_check.side_effect = [
                {"provider": "opencode", "available": True},
                {"provider": "cc-glm", "available": False, "error": "Auth failed", "reason_code": "auth_error"},
            ]

            all_passed, results = checker.run()

            assert not all_passed
            assert results["cc-glm"]["reason_code"] == "auth_error"

    def test_get_first_available_provider(self):
        checker = PreflightChecker(["opencode", "cc-glm", "gemini"])

        with patch.object(checker, '_check_provider') as mock_check:
            mock_check.side_effect = [
                {"provider": "opencode", "available": False},
                {"provider": "cc-glm", "available": True},
                {"provider": "gemini", "available": True},
            ]

            checker.run()
            provider = checker.get_first_available_provider()

            assert provider == "cc-glm"

    def test_dx_runner_missing_reason_code(self):
        checker = PreflightChecker(["opencode"])

        with patch('subprocess.run') as mock_run:
            mock_run.side_effect = FileNotFoundError("dx-runner not found")
            result = checker._check_provider("opencode")

            assert result["reason_code"] == "dx_runner_missing"
