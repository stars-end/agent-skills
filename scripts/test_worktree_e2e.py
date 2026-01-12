#!/usr/bin/env python3
"""
E2E tests for Parallel Agent Infrastructure (Worktrees)

Tests the worktree-setup.sh and worktree-cleanup.sh scripts along with
resource isolation logic from dx-dispatch.py.

Usage:
    python scripts/test_worktree_e2e.py [--remote VM_NAME]
    
    By default runs locally. Use --remote epyc6 to run on a remote VM.
"""

import os
import sys
import subprocess
import tempfile
import shutil
from pathlib import Path
from datetime import datetime

# Test configuration
TEST_BEADS_IDS = ["bd-test-001", "bd-test-002", "bd-test-003"]
TEST_REPO = "agent-skills"  # Use this repo for testing

# Path to scripts (relative to repo root)
SCRIPT_DIR = Path(__file__).parent
WORKTREE_SETUP = SCRIPT_DIR / "worktree-setup.sh"
WORKTREE_CLEANUP = SCRIPT_DIR / "worktree-cleanup.sh"


def log(msg: str, level: str = "INFO"):
    """Log with timestamp."""
    ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    symbol = {"INFO": "ℹ️", "PASS": "✅", "FAIL": "❌", "WARN": "⚠️"}.get(level, "•")
    print(f"[{ts}] {symbol} {msg}")


def run_script(script: Path, args: list, cwd: str = None) -> tuple[int, str, str]:
    """Run a shell script and return (returncode, stdout, stderr)."""
    result = subprocess.run(
        ["bash", str(script)] + args,
        capture_output=True,
        text=True,
        cwd=cwd or str(SCRIPT_DIR)
    )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def compute_resources(beads_id: str) -> dict:
    """
    Compute deterministic resource allocation based on beads ID.
    Mirrors the logic in dx-dispatch.py.
    """
    # Extract numeric part of beads ID or hash it
    # e.g. bd-123 -> 123, bd-abc -> hash(abc) % 1000
    import hashlib
    
    # Get a numeric component from the ID
    id_part = beads_id.replace("bd-", "").replace("test-", "")
    try:
        numeric = int(id_part)
    except ValueError:
        # Hash non-numeric IDs
        numeric = int(hashlib.md5(id_part.encode()).hexdigest(), 16) % 1000
    
    # Calculate resources
    # Port offset range: 0-99 to avoid conflicts
    port_offset = numeric % 100
    
    return {
        "port_frontend": 3000 + port_offset,
        "port_backend": 8000 + port_offset,
        "db_schema": f"test_agent_{numeric % 1000}",
        "beads_id": beads_id,
        "numeric": numeric
    }


class TestResults:
    """Track test results."""
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.tests = []
    
    def record(self, name: str, passed: bool, details: str = ""):
        self.tests.append({"name": name, "passed": passed, "details": details})
        if passed:
            self.passed += 1
            log(f"PASS: {name}", "PASS")
        else:
            self.failed += 1
            log(f"FAIL: {name} - {details}", "FAIL")
    
    def summary(self):
        total = self.passed + self.failed
        log(f"\n📊 Test Summary: {self.passed}/{total} passed", "INFO")
        if self.failed > 0:
            log("Failed tests:", "WARN")
            for t in self.tests:
                if not t["passed"]:
                    log(f"  - {t['name']}: {t['details']}", "WARN")
        return self.failed == 0


def test_worktree_setup_creates_directory(results: TestResults):
    """Test that worktree-setup.sh creates the expected directory structure."""
    beads_id = "bd-test-setup-001"
    expected_path = Path(f"/tmp/agents/{beads_id}/{TEST_REPO}")
    
    # Cleanup first
    if expected_path.exists():
        shutil.rmtree(expected_path.parent, ignore_errors=True)
    
    # Run setup
    rc, stdout, stderr = run_script(WORKTREE_SETUP, [beads_id, TEST_REPO])
    
    if rc == 0 and expected_path.exists():
        # Verify it's a git worktree
        git_file = expected_path / ".git"
        is_worktree = git_file.exists() and git_file.is_file()  # Worktrees have .git as file, not dir
        
        if is_worktree:
            results.record("worktree_setup_creates_directory", True)
        else:
            results.record("worktree_setup_creates_directory", False, ".git is not a worktree marker")
    else:
        results.record("worktree_setup_creates_directory", False, f"rc={rc}, stderr={stderr}")
    
    # Cleanup
    shutil.rmtree(expected_path.parent, ignore_errors=True)


def test_worktree_setup_idempotent(results: TestResults):
    """Test that running setup twice doesn't fail."""
    beads_id = "bd-test-idempotent"
    expected_path = Path(f"/tmp/agents/{beads_id}/{TEST_REPO}")
    
    # Cleanup
    if expected_path.parent.exists():
        shutil.rmtree(expected_path.parent, ignore_errors=True)
    
    # First run
    rc1, stdout1, stderr1 = run_script(WORKTREE_SETUP, [beads_id, TEST_REPO])
    
    # Second run (should succeed or return existing path)
    rc2, stdout2, stderr2 = run_script(WORKTREE_SETUP, [beads_id, TEST_REPO])
    
    if rc1 == 0 and rc2 == 0:
        results.record("worktree_setup_idempotent", True)
    else:
        results.record("worktree_setup_idempotent", False, f"run1: rc={rc1}, run2: rc={rc2}")
    
    # Cleanup
    shutil.rmtree(expected_path.parent, ignore_errors=True)


def test_worktree_cleanup(results: TestResults):
    """Test that worktree-cleanup.sh removes the worktree."""
    beads_id = "bd-test-cleanup"
    expected_path = Path(f"/tmp/agents/{beads_id}/{TEST_REPO}")
    
    # Setup first
    run_script(WORKTREE_SETUP, [beads_id, TEST_REPO])
    
    if not expected_path.exists():
        results.record("worktree_cleanup", False, "Setup failed, skipping cleanup test")
        return
    
    # Run cleanup
    rc, stdout, stderr = run_script(WORKTREE_CLEANUP, [beads_id])
    
    if rc == 0 and not expected_path.parent.exists():
        results.record("worktree_cleanup", True)
    else:
        results.record("worktree_cleanup", False, f"Path still exists: {expected_path.parent.exists()}")


def test_parallel_worktrees(results: TestResults):
    """Test that multiple worktrees can coexist."""
    beads_ids = ["bd-test-parallel-a", "bd-test-parallel-b", "bd-test-parallel-c"]
    all_created = True
    errors = []
    
    # Cleanup first
    for bid in beads_ids:
        path = Path(f"/tmp/agents/{bid}")
        if path.exists():
            shutil.rmtree(path, ignore_errors=True)
    
    # Create all worktrees
    for bid in beads_ids:
        rc, stdout, stderr = run_script(WORKTREE_SETUP, [bid, TEST_REPO])
        expected_path = Path(f"/tmp/agents/{bid}/{TEST_REPO}")
        
        if rc != 0 or not expected_path.exists():
            all_created = False
            errors.append(f"{bid}: rc={rc}")
    
    if all_created:
        # Verify all exist simultaneously
        all_exist = all(
            Path(f"/tmp/agents/{bid}/{TEST_REPO}").exists()
            for bid in beads_ids
        )
        if all_exist:
            results.record("parallel_worktrees", True)
        else:
            results.record("parallel_worktrees", False, "Not all worktrees exist after creation")
    else:
        results.record("parallel_worktrees", False, ", ".join(errors))
    
    # Cleanup
    for bid in beads_ids:
        run_script(WORKTREE_CLEANUP, [bid])


def test_resource_isolation(results: TestResults):
    """Test that different beads IDs get different resource allocations."""
    ids = ["bd-001", "bd-002", "bd-003", "bd-abc", "bd-xyz"]
    allocations = [compute_resources(bid) for bid in ids]
    
    # Check that ports are unique within the set
    ports = [(a["port_frontend"], a["port_backend"]) for a in allocations]
    unique_ports = set(ports)
    
    if len(unique_ports) == len(ports):
        results.record("resource_isolation_unique_ports", True)
    else:
        results.record("resource_isolation_unique_ports", False, "Port collision detected")
    
    # Check that numeric IDs are stable (deterministic)
    r1 = compute_resources("bd-test-stable")
    r2 = compute_resources("bd-test-stable")
    
    if r1 == r2:
        results.record("resource_isolation_deterministic", True)
    else:
        results.record("resource_isolation_deterministic", False, "Non-deterministic resource allocation")


def test_worktree_isolation(results: TestResults):
    """Test that changes in one worktree don't affect another."""
    bid1 = "bd-test-iso-1"
    bid2 = "bd-test-iso-2"
    
    # Setup both
    run_script(WORKTREE_SETUP, [bid1, TEST_REPO])
    run_script(WORKTREE_SETUP, [bid2, TEST_REPO])
    
    path1 = Path(f"/tmp/agents/{bid1}/{TEST_REPO}")
    path2 = Path(f"/tmp/agents/{bid2}/{TEST_REPO}")
    
    if not (path1.exists() and path2.exists()):
        results.record("worktree_isolation", False, "Failed to create both worktrees")
        return
    
    # Create a file in worktree 1
    test_file = path1 / "test_isolation_marker.txt"
    test_file.write_text("isolation test")
    
    # Check it doesn't exist in worktree 2
    other_file = path2 / "test_isolation_marker.txt"
    
    if test_file.exists() and not other_file.exists():
        results.record("worktree_isolation", True)
    else:
        results.record("worktree_isolation", False, f"File leaked: {other_file.exists()}")
    
    # Cleanup
    test_file.unlink(missing_ok=True)
    run_script(WORKTREE_CLEANUP, [bid1])
    run_script(WORKTREE_CLEANUP, [bid2])


def main():
    """Run all E2E tests."""
    log("🚀 Starting Parallel Agent Infrastructure E2E Tests")
    log(f"   Test repo: {TEST_REPO}")
    log(f"   Script dir: {SCRIPT_DIR}")
    
    # Check scripts exist
    if not WORKTREE_SETUP.exists():
        log(f"Script not found: {WORKTREE_SETUP}", "FAIL")
        # Try fetching from origin/master
        log("Attempting to checkout scripts from origin/master...", "INFO")
        subprocess.run(
            ["git", "checkout", "origin/master", "--", "scripts/worktree-setup.sh", "scripts/worktree-cleanup.sh"],
            cwd=str(SCRIPT_DIR.parent),
            capture_output=True
        )
        if not WORKTREE_SETUP.exists():
            log("Failed to checkout scripts", "FAIL")
            sys.exit(1)
    
    results = TestResults()
    
    # Run tests
    test_worktree_setup_creates_directory(results)
    test_worktree_setup_idempotent(results)
    test_worktree_cleanup(results)
    test_parallel_worktrees(results)
    test_resource_isolation(results)
    test_worktree_isolation(results)
    
    # Summary
    success = results.summary()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
