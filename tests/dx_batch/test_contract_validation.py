"""Tests for implement/review machine contracts."""
import json
from pathlib import Path
from unittest.mock import patch

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import ContractValidator


class TestImplementContract:
    """Test implement contract validation."""

    def test_implement_contract_valid(self):
        validator = ContractValidator()

        valid_contract = {
            "phase": "implement",
            "beads_id": "bd-abc123",
            "status": "completed",
            "artifacts": {
                "files_changed": ["src/main.py"],
                "commits": [{"sha": "abc123", "message": "feat: add feature"}],
            },
            "timestamp": "2026-02-21T00:00:00Z",
        }

        valid, errors = validator.validate_implement(valid_contract)
        assert valid, f"Should be valid: {errors}"
        assert len(errors) == 0

    def test_implement_contract_missing_phase(self):
        validator = ContractValidator()

        invalid_contract = {
            "beads_id": "bd-abc123",
            "status": "completed",
            "artifacts": {"files_changed": [], "commits": []},
            "timestamp": "2026-02-21T00:00:00Z",
        }

        valid, errors = validator.validate_implement(invalid_contract)
        assert not valid


class TestReviewContract:
    """Test review contract validation with strict verdict."""

    def test_review_contract_valid_approved(self):
        validator = ContractValidator()

        valid_contract = {
            "phase": "review",
            "beads_id": "bd-abc123",
            "verdict": "APPROVED",
            "findings": [],
            "timestamp": "2026-02-21T00:00:00Z",
        }

        valid, errors = validator.validate_review(valid_contract)
        assert valid, f"Should be valid: {errors}"

    def test_review_contract_invalid_fails_closed(self):
        validator = ContractValidator()

        invalid_contracts = [
            {},
            {"phase": "review"},
            {"phase": "review", "beads_id": "bd-x"},
            {"phase": "review", "beads_id": "bd-x", "verdict": "INVALID"},
        ]

        for contract in invalid_contracts:
            valid, errors = validator.validate_review(contract)
            assert not valid, f"Should be invalid: {contract}"

    def test_verdict_enum_enforced(self):
        validator = ContractValidator()

        invalid_verdicts = ["approved", "Approved", "APPROVAL", "needs-revision", ""]

        for verdict in invalid_verdicts:
            contract = {
                "phase": "review",
                "beads_id": "bd-x",
                "verdict": verdict,
                "findings": [],
                "timestamp": "2026-02-21T00:00:00Z",
            }
            valid, errors = validator.validate_review(contract)
            assert not valid, f"Verdict '{verdict}' should be invalid"


class TestMissingRequiredFields:
    """Test that missing required fields fail validation."""

    def test_missing_required_fields_fail_implement(self):
        validator = ContractValidator()

        required_fields = ["phase", "beads_id", "status", "artifacts", "timestamp"]
        base = {
            "phase": "implement",
            "beads_id": "bd-x",
            "status": "completed",
            "artifacts": {"files_changed": [], "commits": []},
            "timestamp": "2026-02-21T00:00:00Z",
        }

        for field in required_fields:
            contract = dict(base)
            del contract[field]
            valid, errors = validator.validate_implement(contract)
            assert not valid, f"Should fail without {field}"
