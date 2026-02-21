"""Tests for separate review run + strict verdict."""
import json
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import ContractValidator, Phase, Verdict


class TestReviewFlow:
    """Test review flow requirements."""

    def test_verdict_enum_enforced(self):
        validator = ContractValidator()

        valid_verdicts = ["APPROVED", "REVISION_REQUIRED", "BLOCKED"]
        for verdict in valid_verdicts:
            contract = {
                "phase": "review",
                "beads_id": "bd-v",
                "verdict": verdict,
                "findings": [],
                "timestamp": "2026-02-21T00:00:00Z",
            }
            valid, errors = validator.validate_review(contract)
            assert valid, f"Verdict {verdict} should be valid: {errors}"

        invalid_verdicts = ["approved", "Approved", "REVISION", "NEEDS_WORK", ""]
        for verdict in invalid_verdicts:
            contract = {
                "phase": "review",
                "beads_id": "bd-v",
                "verdict": verdict,
                "findings": [],
                "timestamp": "2026-02-21T00:00:00Z",
            }
            valid, errors = validator.validate_review(contract)
            assert not valid, f"Verdict {verdict} should be invalid"

    def test_findings_required_on_revision_required(self):
        validator = ContractValidator()

        contract_without_findings = {
            "phase": "review",
            "beads_id": "bd-rev",
            "verdict": "REVISION_REQUIRED",
            "findings": [],
            "timestamp": "2026-02-21T00:00:00Z",
        }
        valid, errors = validator.validate_review(contract_without_findings)
        assert not valid
        assert any("findings" in e.lower() for e in errors)

        contract_with_findings = {
            "phase": "review",
            "beads_id": "bd-rev",
            "verdict": "REVISION_REQUIRED",
            "findings": [{"type": "major", "message": "Missing tests"}],
            "timestamp": "2026-02-21T00:00:00Z",
        }
        valid, errors = validator.validate_review(contract_with_findings)
        assert valid, f"Should be valid: {errors}"
