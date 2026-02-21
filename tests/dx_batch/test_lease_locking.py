"""Tests for strict per-item lease locking."""
import json
import os
import tempfile
import time
from pathlib import Path
from unittest.mock import patch

import pytest

import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import LeaseLock, now_utc


class TestLeaseLocking:
    """Test strict per-item lease locking."""

    def test_duplicate_start_blocked(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            lock1 = LeaseLock("test-wave", "bd-test123", 1, 60)
            lock2 = LeaseLock("test-wave", "bd-test123", 1, 60)

            assert lock1.acquire(), "First lock should succeed"
            assert not lock2.acquire(), "Second lock should be blocked"

            lock1.release()
            assert lock2.acquire(), "Lock should succeed after release"
            lock2.release()

    def test_stale_lease_recovered(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            lock = LeaseLock("test-wave", "bd-stale", 1, 0)
            assert lock.acquire()

            stale_data = {
                "wave_id": "test-wave",
                "beads_id": "bd-stale",
                "attempt": 1,
                "acquired_at": "2020-01-01T00:00:00Z",
                "pid": 99999,
                "ttl_minutes": 0,
            }
            lock.lease_file.write_text(json.dumps(stale_data))

            assert lock.is_stale(), "Lease should be stale"
            assert lock.force_release_if_stale(), "Should force release stale lease"

            new_lock = LeaseLock("test-wave", "bd-stale", 1)
            assert new_lock.acquire(), "Should acquire after stale release"
            new_lock.release()

    def test_attempt_scoped_leases(self, tmp_path):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            lock1 = LeaseLock("test-wave", "bd-attempt-scope", attempt=1)
            lock2 = LeaseLock("test-wave", "bd-attempt-scope", attempt=2)

            assert lock1.acquire(), "Attempt 1 lock should succeed"
            assert lock2.acquire(), "Attempt 2 lock should succeed (different scope)"

            assert lock1.lease_key != lock2.lease_key, "Lease keys should differ"

            lock1.release()
            lock2.release()
