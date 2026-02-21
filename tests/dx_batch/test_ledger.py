"""Tests for single ledger per item + run history."""
import json
import os
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import Ledger, now_utc


class TestLedger:
    """Test per-item ledger with immutable run records."""

    def test_item_ledger_fields_exact(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            ledger = Ledger("test-wave", "bd-ledger-fields")

            record = {
                "provider": "opencode",
                "run_instance": "opencode-abc123",
                "attempt": 1,
                "state": "implementing",
                "started_at": now_utc(),
                "outcome_path": "/tmp/outcome.json",
            }
            ledger.append_run(record)

            assert ledger.ledger_file.exists()
            saved = ledger.get_latest_run()

            assert saved["provider"] == "opencode"
            assert saved["run_instance"] == "opencode-abc123"
            assert saved["attempt"] == 1

    def test_atomic_write_no_partial_json(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            ledger = Ledger("test-wave", "bd-atomic")

            for i in range(10):
                record = {
                    "provider": "opencode",
                    "run_instance": f"run-{i}",
                    "attempt": i + 1,
                    "state": "implementing",
                    "started_at": now_utc(),
                    "outcome_path": f"/tmp/outcome-{i}.json",
                }
                ledger.append_run(record)

            all_runs = ledger.get_all_runs()
            assert len(all_runs) == 10

    def test_resume_uses_existing_ledger(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            ledger = Ledger("test-wave", "bd-resume")

            for i in range(3):
                ledger.append_run({
                    "provider": "opencode",
                    "run_instance": f"run-{i}",
                    "attempt": i + 1,
                    "state": "implementing",
                    "started_at": now_utc(),
                    "outcome_path": f"/tmp/outcome-{i}.json",
                })

            new_ledger = Ledger("test-wave", "bd-resume")
            assert new_ledger.get_attempt_count() == 3
