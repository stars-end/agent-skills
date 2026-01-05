#!/usr/bin/env python3
"""
test_p6_integration.py - Integration tests for P6 Multi-VM Orchestration

Tests:
1. VM endpoints config loading
2. Health checks for all VMs
3. dx-dispatch to each VM
4. Slack audit trail verification
"""

import os
import sys
import json
import subprocess
from pathlib import Path
from datetime import datetime

# Test results
results = {"passed": [], "failed": [], "skipped": []}


def log(msg: str, level: str = "INFO"):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] [{level}] {msg}")


def run_test(name: str, test_func):
    """Run a test and record result."""
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


# =============================================================================
# Test 1: Config File Exists
# =============================================================================

def test_config_exists():
    """Test vm-endpoints.json exists."""
    config_path = Path.home() / ".agent-skills" / "vm-endpoints.json"
    if config_path.exists():
        with open(config_path) as f:
            data = json.load(f)
        vms = list(data.get("vms", {}).keys())
        return True, f"Config found with VMs: {', '.join(vms)}"
    return False, "Config file not found"


# =============================================================================
# Test 2: dx-dispatch --list
# =============================================================================

def test_dx_dispatch_list():
    """Test dx-dispatch --list works."""
    script = Path.home() / "agent-skills" / "scripts" / "dx-dispatch.py"
    result = subprocess.run(
        ["python3", str(script), "--list"],
        capture_output=True, text=True, timeout=60
    )
    
    if result.returncode == 0 and "Available VMs" in result.stdout:
        # Count online VMs
        online_count = result.stdout.count("✅ Online")
        return True, f"{online_count} VMs online"
    return False, result.stderr or "Unknown error"


# =============================================================================
# Test 3: Health Check Each VM
# =============================================================================

def test_health_homedesktop():
    """Health check for homedesktop."""
    result = subprocess.run(
        ["curl", "-s", "http://localhost:4105/global/health"],
        capture_output=True, text=True, timeout=5
    )
    if result.returncode == 0:
        data = json.loads(result.stdout)
        if data.get("healthy"):
            return True, f"v{data.get('version')}"
    return False, "Not healthy"


def test_health_macmini():
    """Health check for macmini via SSH."""
    result = subprocess.run(
        ["ssh", "fengning@macmini", "curl -s http://localhost:4105/global/health"],
        capture_output=True, text=True, timeout=15
    )
    if result.returncode == 0:
        data = json.loads(result.stdout)
        if data.get("healthy"):
            return True, f"v{data.get('version')}"
    return False, "Not healthy"


def test_health_epyc6():
    """Health check for epyc6 via SSH."""
    result = subprocess.run(
        ["ssh", "feng@epyc6", "curl -s http://localhost:4105/global/health"],
        capture_output=True, text=True, timeout=15
    )
    if result.returncode == 0:
        data = json.loads(result.stdout)
        if data.get("healthy"):
            return True, f"v{data.get('version')}"
    return False, "Not healthy"


# =============================================================================
# Test 4: Config Deployed to All VMs
# =============================================================================

def test_config_on_macmini():
    """Check config exists on macmini."""
    result = subprocess.run(
        ["ssh", "fengning@macmini", "cat ~/.agent-skills/vm-endpoints.json"],
        capture_output=True, text=True, timeout=10
    )
    if result.returncode == 0:
        data = json.loads(result.stdout)
        return True, f"Config with {len(data.get('vms', {}))} VMs"
    return False, "Config not found"


def test_config_on_epyc6():
    """Check config exists on epyc6."""
    result = subprocess.run(
        ["ssh", "feng@epyc6", "cat ~/.agent-skills/vm-endpoints.json"],
        capture_output=True, text=True, timeout=10
    )
    if result.returncode == 0:
        data = json.loads(result.stdout)
        return True, f"Config with {len(data.get('vms', {}))} VMs"
    return False, "Config not found"


# =============================================================================
# Test 5: Slack Audit Token Available
# =============================================================================

def test_slack_token():
    """Check Slack token is available for audit."""
    token = os.environ.get("SLACK_MCP_XOXP_TOKEN") or os.environ.get("SLACK_BOT_TOKEN")
    if token and token.startswith("xoxb-"):
        return True, f"Token found ({len(token)} chars)"
    return False, "No Slack token"


# =============================================================================
# Run All Tests
# =============================================================================

def main():
    log("=" * 70)
    log("P6 Multi-VM Orchestration Integration Tests")
    log("=" * 70)
    
    # Core tests
    run_test("1. Config file exists", test_config_exists)
    run_test("2. dx-dispatch --list", test_dx_dispatch_list)
    
    # Health checks
    run_test("3a. Health: homedesktop", test_health_homedesktop)
    run_test("3b. Health: macmini", test_health_macmini)
    run_test("3c. Health: epyc6", test_health_epyc6)
    
    # Config deployment
    run_test("4a. Config on macmini", test_config_on_macmini)
    run_test("4b. Config on epyc6", test_config_on_epyc6)
    
    # Slack
    run_test("5. Slack token available", test_slack_token)
    
    # Summary
    log("")
    log("=" * 70)
    log("RESULTS SUMMARY")
    log("=" * 70)
    log(f"Passed: {len(results['passed'])}")
    log(f"Failed: {len(results['failed'])}")
    
    if results["failed"]:
        log("")
        log("Failed tests:")
        for name, msg in results["failed"]:
            log(f"  - {name}: {msg}", "FAIL")
    
    if results["passed"]:
        log("")
        log("Passed tests:")
        for name, msg in results["passed"]:
            log(f"  - {name}: {msg}", "PASS")
    
    return 0 if not results["failed"] else 1


if __name__ == "__main__":
    sys.exit(main())
