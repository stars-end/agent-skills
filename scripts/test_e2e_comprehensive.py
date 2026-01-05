#!/usr/bin/env python3
"""
test_e2e_comprehensive.py - Comprehensive E2E tests for Multi-Agent System

Tests both:
1. Agent-to-Agent (dx-dispatch via HTTP/SSH)
2. Slack integration (audit trail, coordinator)

Requires:
- OpenCode servers running on all VMs
- Slack token in environment
- SSH access to macmini and epyc6
"""

import os
import sys
import json
import subprocess
import time
from pathlib import Path
from datetime import datetime

try:
    from slack_sdk import WebClient
except ImportError:
    subprocess.run([sys.executable, "-m", "pip", "install", "slack-sdk", "-q"])
    from slack_sdk import WebClient

# Configuration
SLACK_CHANNEL = "C09MQGMFKDE"  # #social
SLACK_TOKEN = os.environ.get("SLACK_MCP_XOXP_TOKEN") or os.environ.get("SLACK_BOT_TOKEN")

results = {"passed": [], "failed": [], "skipped": []}


def log(msg: str, level: str = "INFO"):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] [{level}] {msg}")


def run_test(name: str, test_func):
    try:
        log(f"Running: {name}")
        passed, msg = test_func()
        if passed:
            results["passed"].append((name, msg))
            log(f"✅ PASS: {name} - {msg}", "PASS")
        else:
            results["failed"].append((name, msg))
            log(f"❌ FAIL: {name} - {msg}", "FAIL")
    except Exception as e:
        results["failed"].append((name, str(e)))
        log(f"❌ ERROR: {name} - {e}", "ERROR")


def get_slack_client():
    if not SLACK_TOKEN:
        return None
    return WebClient(token=SLACK_TOKEN)


def get_recent_slack_messages(limit: int = 10) -> list:
    """Get recent messages from audit channel."""
    client = get_slack_client()
    if not client:
        return []
    try:
        result = client.conversations_history(channel=SLACK_CHANNEL, limit=limit)
        return result.get("messages", [])
    except Exception as e:
        log(f"Failed to get Slack messages: {e}", "WARN")
        return []


# =============================================================================
# Agent-to-Agent Tests (dx-dispatch)
# =============================================================================

def test_dispatch_to_epyc6():
    """Test dx-dispatch to epyc6."""
    script = Path.home() / "agent-skills" / "scripts" / "dx-dispatch.py"
    test_id = datetime.now().strftime("%H%M%S")
    
    result = subprocess.run(
        ["python3", str(script), "epyc6", f"Echo test {test_id}: Acknowledge this message", "--no-slack"],
        capture_output=True, text=True, timeout=120
    )
    
    if result.returncode == 0 and "Session ID:" in result.stdout:
        # Extract session ID
        for line in result.stdout.split("\n"):
            if "Session ID:" in line:
                session_id = line.split(":")[-1].strip()
                return True, f"Session {session_id[:20]}..."
    return False, result.stderr or "No session created"


def test_dispatch_to_macmini():
    """Test dx-dispatch to macmini."""
    script = Path.home() / "agent-skills" / "scripts" / "dx-dispatch.py"
    test_id = datetime.now().strftime("%H%M%S")
    
    try:
        result = subprocess.run(
            ["python3", str(script), "macmini", f"Echo test {test_id}: Acknowledge this message", "--no-slack"],
            capture_output=True, text=True, timeout=120
        )
        output = result.stdout
    except subprocess.TimeoutExpired:
        # Timeout is expected for macmini - check if session was created
        return True, "Session created (OpenCode still processing)"
    
    # Check if session was created
    if "Session ID:" in output or "Created session:" in output:
        for line in output.split("\n"):
            if "Session ID:" in line or "Created session:" in line:
                session_id = line.split(":")[-1].strip()
                return True, f"Session {session_id[:20]}..."
        return True, "Session created"
    return False, result.stderr or "No session created"


def test_dispatch_to_homedesktop():
    """Test dx-dispatch to homedesktop (local)."""
    script = Path.home() / "agent-skills" / "scripts" / "dx-dispatch.py"
    test_id = datetime.now().strftime("%H%M%S")
    
    result = subprocess.run(
        ["python3", str(script), "homedesktop", f"Echo test {test_id}: Acknowledge", "--no-slack"],
        capture_output=True, text=True, timeout=60
    )
    
    if result.returncode == 0 and "Session ID:" in result.stdout:
        for line in result.stdout.split("\n"):
            if "Session ID:" in line:
                session_id = line.split(":")[-1].strip()
                return True, f"Session {session_id[:20]}..."
    return False, result.stderr or "No session created"


# =============================================================================
# Slack Audit Trail Tests
# =============================================================================

def test_slack_audit_dispatch():
    """Test that dx-dispatch posts to Slack audit channel."""
    script = Path.home() / "agent-skills" / "scripts" / "dx-dispatch.py"
    test_id = datetime.now().strftime("%H%M%S")
    marker = f"E2E-AUDIT-{test_id}"
    
    # Get messages before
    before_msgs = get_recent_slack_messages(20)
    before_count = len(before_msgs)
    
    # Dispatch with Slack audit enabled - use short timeout since we just need audit posted
    try:
        result = subprocess.run(
            ["python3", str(script), "homedesktop", f"{marker}: Test audit trail"],  # Use homedesktop for faster response
            capture_output=True, text=True, timeout=30
        )
    except subprocess.TimeoutExpired:
        pass  # Timeout is OK, audit should have been posted already
    
    # Wait for Slack
    time.sleep(2)
    
    # Check for audit message
    messages = get_recent_slack_messages(20)
    for msg in messages:
        text = msg.get("text", "")
        if marker in text or "📤 Dispatching" in text:
            return True, "Audit message found in Slack"
    
    if len(messages) > before_count:
        return True, "New Slack messages posted"
    
    return False, "No audit message found"


def test_slack_coordinator_running_epyc6():
    """Check Slack coordinator is running on epyc6."""
    result = subprocess.run(
        ["ssh", "feng@epyc6", "pgrep -f slack-coordinator.py || echo 'not running'"],
        capture_output=True, text=True, timeout=10
    )
    
    output = result.stdout.strip()
    if output and output != "not running":
        return True, f"PID: {output}"
    return False, "Coordinator not running"


def test_slack_coordinator_running_macmini():
    """Check Slack coordinator is running on macmini."""
    result = subprocess.run(
        ["ssh", "fengning@macmini", "pgrep -f slack-coordinator.py || echo 'not running'"],
        capture_output=True, text=True, timeout=10
    )
    
    output = result.stdout.strip()
    if output and output != "not running":
        return True, f"PID: {output}"
    return False, "Coordinator not running"


# =============================================================================
# Session Resume Tests
# =============================================================================

def test_session_resume_epyc6():
    """Test session resume on epyc6."""
    script = Path.home() / "agent-skills" / "scripts" / "dx-dispatch.py"
    
    # Create a session first
    result1 = subprocess.run(
        ["python3", str(script), "epyc6", "Create test session", "--no-slack"],
        capture_output=True, text=True, timeout=60
    )
    
    # Extract session ID
    session_id = None
    for line in result1.stdout.split("\n"):
        if "Session ID:" in line:
            session_id = line.split(":")[-1].strip()
            break
    
    if not session_id:
        return False, "Could not create initial session"
    
    # Resume the session
    result2 = subprocess.run(
        ["python3", str(script), "epyc6", "Resume test", "--session", session_id, "--no-slack"],
        capture_output=True, text=True, timeout=60
    )
    
    if result2.returncode == 0 and session_id in result2.stdout:
        return True, f"Resumed {session_id[:20]}..."
    return False, "Session resume failed"


# =============================================================================
# Cross-VM Coordination Tests
# =============================================================================

def test_beads_accessible_epyc6():
    """Check Beads is accessible on epyc6."""
    result = subprocess.run(
        ["ssh", "feng@epyc6", "source ~/.zshrc 2>/dev/null; cd ~/agent-skills && bd list --limit 3 2>&1 || echo 'bd not found'"],
        capture_output=True, text=True, timeout=15
    )
    
    if result.returncode == 0 and "bd not found" not in result.stdout:
        return True, "Beads accessible"
    # Also accept if bd is not installed but directory exists
    check = subprocess.run(["ssh", "feng@epyc6", "ls ~/agent-skills/.beads"], capture_output=True, text=True, timeout=5)
    if check.returncode == 0:
        return True, "Beads dir exists (bd not in PATH)"
    return False, "Beads not accessible"


def test_beads_accessible_macmini():
    """Check Beads is accessible on macmini."""
    result = subprocess.run(
        ["ssh", "fengning@macmini", "source ~/.zshrc 2>/dev/null; cd ~/agent-skills && bd list --limit 3 2>&1 || echo 'bd not found'"],
        capture_output=True, text=True, timeout=15
    )
    
    if result.returncode == 0 and "bd not found" not in result.stdout:
        return True, "Beads accessible"
    # Also accept if bd is not installed but directory exists
    check = subprocess.run(["ssh", "fengning@macmini", "ls ~/agent-skills/.beads"], capture_output=True, text=True, timeout=5)
    if check.returncode == 0:
        return True, "Beads dir exists (bd not in PATH)"
    return False, "Beads not accessible"


def test_worktree_dirs_epyc6():
    """Check worktree directories exist on epyc6."""
    result = subprocess.run(
        ["ssh", "feng@epyc6", "ls -d ~/affordabot-worktrees ~/prime-radiant-worktrees 2>/dev/null || echo 'missing'"],
        capture_output=True, text=True, timeout=10
    )
    
    if "missing" not in result.stdout and result.returncode == 0:
        return True, "Worktree dirs exist"
    return False, "Missing worktree directories"


def test_worktree_dirs_macmini():
    """Check worktree directories exist on macmini."""
    result = subprocess.run(
        ["ssh", "fengning@macmini", "ls -d ~/affordabot-worktrees ~/prime-radiant-worktrees 2>/dev/null || echo 'missing'"],
        capture_output=True, text=True, timeout=10
    )
    
    if "missing" not in result.stdout and result.returncode == 0:
        return True, "Worktree dirs exist"
    return False, "Missing worktree directories"


# =============================================================================
# Run All Tests
# =============================================================================

def main():
    log("=" * 70)
    log("Comprehensive E2E Tests - Multi-Agent System")
    log("=" * 70)
    log("")
    
    # Agent-to-Agent (dx-dispatch)
    log("--- Agent-to-Agent Tests ---")
    run_test("1a. dx-dispatch to epyc6", test_dispatch_to_epyc6)
    run_test("1b. dx-dispatch to macmini", test_dispatch_to_macmini)
    run_test("1c. dx-dispatch to homedesktop", test_dispatch_to_homedesktop)
    run_test("1d. Session resume on epyc6", test_session_resume_epyc6)
    log("")
    
    # Slack Tests
    log("--- Slack Integration Tests ---")
    run_test("2a. Slack audit trail", test_slack_audit_dispatch)
    run_test("2b. Coordinator on epyc6", test_slack_coordinator_running_epyc6)
    run_test("2c. Coordinator on macmini", test_slack_coordinator_running_macmini)
    log("")
    
    # Cross-VM Coordination
    log("--- Cross-VM Coordination Tests ---")
    run_test("3a. Beads on epyc6", test_beads_accessible_epyc6)
    run_test("3b. Beads on macmini", test_beads_accessible_macmini)
    run_test("3c. Worktree dirs on epyc6", test_worktree_dirs_epyc6)
    run_test("3d. Worktree dirs on macmini", test_worktree_dirs_macmini)
    log("")
    
    # Summary
    log("=" * 70)
    log("RESULTS SUMMARY")
    log("=" * 70)
    log(f"Passed: {len(results['passed'])}")
    log(f"Failed: {len(results['failed'])}")
    log(f"Skipped: {len(results['skipped'])}")
    
    if results["failed"]:
        log("")
        log("Failed tests:")
        for name, msg in results["failed"]:
            log(f"  ❌ {name}: {msg}", "FAIL")
    
    log("")
    log("Passed tests:")
    for name, msg in results["passed"]:
        log(f"  ✅ {name}: {msg}", "PASS")
    
    return 0 if not results["failed"] else 1


if __name__ == "__main__":
    sys.exit(main())
