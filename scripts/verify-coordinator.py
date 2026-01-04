#!/usr/bin/env python3
"""
verify-coordinator.py - Automated coordinator verification tests

Runs verification tests for the multi-agent coordination system.
Part of bd-agent-skills-4l0 implementation.

Usage:
    python verify-coordinator.py [--vm epyc6|macmini] [--quick]
"""

import subprocess
import sys
import json
import time
import argparse
from pathlib import Path

try:
    import requests
except ImportError:
    print("❌ requests not installed. Run: pip install requests")
    sys.exit(1)

# Default configuration
DEFAULT_OPENCODE_URL = "http://localhost:4105"
VM_ENDPOINTS = {
    "epyc6": "http://localhost:4105",
    "macmini": "http://macmini.tail76761.ts.net:4105",
}


class CoordinatorVerifier:
    def __init__(self, vm: str = None):
        self.vm = vm or "local"
        self.base_url = VM_ENDPOINTS.get(vm, DEFAULT_OPENCODE_URL)
        self.passed = 0
        self.failed = 0
        self.errors = []
    
    def log(self, status: str, message: str):
        print(f"{status} {message}")
    
    def test_opencode_health(self):
        """Test OpenCode server health."""
        try:
            resp = requests.get(f"{self.base_url}/global/health", timeout=5)
            if resp.status_code == 200 and resp.json().get("healthy"):
                self.log("✅", f"OpenCode health OK on {self.vm}")
                self.passed += 1
                return True
            else:
                self.log("❌", f"OpenCode health failed on {self.vm}")
                self.failed += 1
                self.errors.append(f"Health check returned: {resp.text}")
                return False
        except requests.RequestException as e:
            self.log("❌", f"OpenCode unreachable on {self.vm}: {e}")
            self.failed += 1
            self.errors.append(str(e))
            return False
    
    def test_session_list(self):
        """Test session listing."""
        try:
            resp = requests.get(f"{self.base_url}/session", timeout=5)
            if resp.status_code == 200:
                sessions = resp.json()
                self.log("✅", f"Session list OK: {len(sessions)} sessions on {self.vm}")
                self.passed += 1
                return sessions
            else:
                self.log("❌", f"Session list failed: {resp.status_code}")
                self.failed += 1
                return []
        except requests.RequestException as e:
            self.log("❌", f"Session list error: {e}")
            self.failed += 1
            return []
    
    def test_session_create(self):
        """Test session creation."""
        try:
            resp = requests.post(
                f"{self.base_url}/session",
                json={"title": f"verify-test-{int(time.time())}"},
                timeout=10
            )
            if resp.status_code == 200:
                session_id = resp.json().get("id")
                if session_id and session_id.startswith("ses_"):
                    self.log("✅", f"Session created: {session_id[:16]}...")
                    self.passed += 1
                    return session_id
            self.log("❌", f"Session creation failed: {resp.text}")
            self.failed += 1
            return None
        except requests.RequestException as e:
            self.log("❌", f"Session creation error: {e}")
            self.failed += 1
            return None
    
    def test_worktree_directory(self):
        """Test worktree directory exists."""
        wt_dirs = [
            Path.home() / "affordabot-worktrees",
            Path.home() / "prime-radiant-worktrees",
        ]
        for wt_dir in wt_dirs:
            if wt_dir.exists():
                self.log("✅", f"Worktree directory exists: {wt_dir.name}")
                self.passed += 1
            else:
                self.log("❌", f"Worktree directory missing: {wt_dir}")
                self.failed += 1
    
    def test_beads_cli(self):
        """Test Beads CLI available."""
        try:
            result = subprocess.run(
                ["bd", "--version"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                self.log("✅", f"Beads CLI: {result.stdout.strip()}")
                self.passed += 1
                return True
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        
        self.log("⚠️ ", "Beads CLI not found (optional)")
        return False
    
    def test_beads_merge_driver(self):
        """Test Beads merge driver configured."""
        try:
            result = subprocess.run(
                ["git", "config", "--global", "--get", "merge.beads.driver"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                self.log("✅", f"Beads merge driver configured")
                self.passed += 1
                return True
        except subprocess.TimeoutExpired:
            pass
        
        self.log("❌", "Beads merge driver not configured")
        self.failed += 1
        return False
    
    def test_coordinator_systemd(self):
        """Test coordinator systemd service."""
        try:
            result = subprocess.run(
                ["systemctl", "--user", "is-active", "slack-coordinator"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                self.log("✅", "Coordinator systemd service: running")
                self.passed += 1
                return True
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass
        
        self.log("❌", "Coordinator systemd service: not running")
        self.failed += 1
        return False
    
    def run_all(self, quick: bool = False):
        """Run all verification tests."""
        print(f"\n{'='*50}")
        print(f"Multi-Agent Coordinator Verification")
        print(f"Target: {self.vm} ({self.base_url})")
        print(f"{'='*50}\n")
        
        # Core tests
        self.test_opencode_health()
        self.test_session_list()
        self.test_coordinator_systemd()
        
        if not quick:
            self.test_session_create()
            self.test_worktree_directory()
            self.test_beads_cli()
            self.test_beads_merge_driver()
        
        # Summary
        print(f"\n{'='*50}")
        print(f"Results: {self.passed} passed, {self.failed} failed")
        print(f"{'='*50}\n")
        
        if self.errors:
            print("Errors:")
            for err in self.errors:
                print(f"  - {err}")
        
        return self.failed == 0


def main():
    parser = argparse.ArgumentParser(description="Verify multi-agent coordinator")
    parser.add_argument("--vm", choices=["epyc6", "macmini"], help="VM to test")
    parser.add_argument("--quick", action="store_true", help="Run quick tests only")
    args = parser.parse_args()
    
    verifier = CoordinatorVerifier(args.vm)
    success = verifier.run_all(args.quick)
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
