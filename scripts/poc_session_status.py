#!/usr/bin/env python3
"""
poc_session_status.py - Test OpenCode session status API behavior

Goals:
1. Create a session
2. Dispatch a simple task
3. Poll the session to see what status/state info is available
4. Understand when/how we can detect completion
"""

import os
import sys
import json
import time
import subprocess
from datetime import datetime

def log(msg):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}")

def ssh_curl(vm_ssh: str, endpoint: str, method: str = "GET", data: dict = None) -> dict:
    """Execute curl via SSH to VM's localhost:4105."""
    if method == "GET":
        cmd = f'curl -s http://localhost:4105{endpoint}'
    else:
        payload = json.dumps(data).replace("'", "'\\''")
        cmd = f"curl -s -X POST http://localhost:4105{endpoint} -H 'Content-Type: application/json' -d '{payload}'"
    
    result = subprocess.run(
        ["ssh", vm_ssh, cmd],
        capture_output=True, text=True, timeout=30
    )
    
    if result.returncode == 0 and result.stdout.strip():
        try:
            return json.loads(result.stdout)
        except:
            return {"raw": result.stdout}
    return {"error": result.stderr or "No response"}


def main():
    vm = "feng@epyc6"  # Test on epyc6
    
    log("=== POC: Test OpenCode Session Status API ===")
    log("")
    
    # 1. Create a session
    log("1. Creating session...")
    session_resp = ssh_curl(vm, "/session", "POST", {"title": "poc-status-test"})
    session_id = session_resp.get("id")
    log(f"   Session ID: {session_id}")
    log(f"   Full response: {json.dumps(session_resp, indent=2)}")
    
    if not session_id:
        log("Failed to create session")
        return
    
    # 2. Check initial session state
    log("")
    log("2. Checking initial session state...")
    state = ssh_curl(vm, f"/session/{session_id}")
    log(f"   Initial state: {json.dumps(state, indent=2)}")
    
    # 3. Send a task (simple echo)
    log("")
    log("3. Sending simple task...")
    task = "Echo back: 'POC test complete'. Then stop."
    
    # Use non-blocking approach - just POST and check status
    msg_resp = ssh_curl(vm, f"/session/{session_id}/message", "POST", {
        "parts": [{"type": "text", "text": task}]
    })
    log(f"   Message response: {json.dumps(msg_resp, indent=2)}")
    
    # 4. Poll session status every 5 seconds for 60 seconds
    log("")
    log("4. Polling session status for 60 seconds...")
    
    for i in range(12):  # 12 x 5s = 60s
        time.sleep(5)
        state = ssh_curl(vm, f"/session/{session_id}")
        log(f"   [{i*5}s] Status: {json.dumps(state, indent=2)[:200]}...")
        
        # Check if there's a completion indicator
        if state.get("status") == "complete" or state.get("done"):
            log("   Session appears complete!")
            break
    
    # 5. Try listing sessions to see their states
    log("")
    log("5. Listing all sessions to see available state info...")
    sessions = ssh_curl(vm, "/session")
    log(f"   Sessions: {json.dumps(sessions, indent=2)[:500]}...")
    
    log("")
    log("=== POC Complete ===")


if __name__ == "__main__":
    main()
