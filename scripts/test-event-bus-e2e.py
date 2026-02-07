#!/usr/bin/env python3
"""
Comprehensive E2E Test for Agent Event Bus - All 5 Workflows (Persistent Session)

Tests:
1. Nightly Dispatcher - DISPATCH_REQUEST event
2. Jules Dispatch - JULES_COMPLETE event
3. OpenCode Dispatch - PR_CREATED event  
4. HITL OpenClawd - Thread reply with slack_thread_ts
5. Code Review - REVIEW_COMPLETE event
"""

import json
import subprocess
import sys
import time
import threading
import os
from datetime import datetime

# Find slack-mcp-server binary (cross-platform)
SLACK_MCP_BIN = os.path.expanduser("~/go/bin/slack-mcp-server")
if not os.path.exists(SLACK_MCP_BIN):
    SLACK_MCP_BIN = "/home/linuxbrew/.linuxbrew/bin/slack-mcp-server"
if not os.path.exists(SLACK_MCP_BIN):
    SLACK_MCP_BIN = "slack-mcp-server"  # Hope it's in PATH

SLACK_MCP_CMD = [SLACK_MCP_BIN, "--transport", "stdio"]
FLEET_EVENTS_CHANNEL = "C0A8YU9JW06"  # #fleet-events (ID)

class MCPClient:
    def __init__(self):
        self.proc = subprocess.Popen(
            SLACK_MCP_CMD,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1  # Line buffered
        )
        self.response_lock = threading.Lock()
        self.responses = {}
        self.running = True
        
        # Start reader threads
        self.stdout_thread = threading.Thread(target=self._read_stdout)
        self.stderr_thread = threading.Thread(target=self._read_stderr)
        self.stdout_thread.daemon = True
        self.stderr_thread.daemon = True
        self.stdout_thread.start()
        self.stderr_thread.start()

    def _read_stdout(self):
        while self.running:
            line = self.proc.stdout.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            
            # Check if it's a JSON-RPC response
            if line.startswith('{"jsonrpc"'):
                try:
                    data = json.loads(line)
                    if "id" in data:
                        with self.response_lock:
                            self.responses[data["id"]] = data
                except:
                    print(f"DEBUG: Failed to parse JSON: {line}")
            else:
                # print(f"STDOUT: {line}") # Debug
                pass

    def _read_stderr(self):
        while self.running:
            line = self.proc.stderr.readline()
            if not line:
                break
            # print(f"STDERR: {line.strip()}")

    def send_request(self, method, params=None, req_id=None):
        if req_id is None:
            req_id = int(time.time() * 1000)
            
        req = {
            "jsonrpc": "2.0",
            "id": req_id,
            "method": method
        }
        if params:
            req["params"] = params
            
        json_req = json.dumps(req)
        # print(f"SENDING: {json_req}")
        try:
            self.proc.stdin.write(json_req + "\n")
            self.proc.stdin.flush()
        except BrokenPipeError:
            print("❌ Error: MCP Server process died")
            sys.exit(1)
            
        return req_id

    def wait_for_response(self, req_id, timeout=10):
        start = time.time()
        while time.time() - start < timeout:
            with self.response_lock:
                if req_id in self.responses:
                    return self.responses[req_id]
            time.sleep(0.1)
        return {"error": {"message": "Timeout waiting for response"}}

    def close(self):
        self.running = False
        try:
            self.proc.terminate()
        except:
            pass

def post_event(client, name, event_type, payload, repo="prime-radiant-ai", beads_id=None, thread_ts=None):
    if beads_id is None:
        beads_id = f"bd-test-{int(time.time()) % 10000}"
    event_id = f"evt_{int(time.time())}_{name.lower().split()[0]}"
    event = {
        "event_id": event_id,
        "event_type": event_type,
        "version": "1.0",
        "repo": repo,
        "beads_id": beads_id,
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "sender": "e2e-test",
        "payload": payload
    }
    
    args = {
        "channel_id": FLEET_EVENTS_CHANNEL,
        "content_type": "text/plain",
        "payload": json.dumps(event)  # Compact JSON for reliable parsing
    }
    if thread_ts:
        args["thread_ts"] = thread_ts
        
    req_id = client.send_request("tools/call", {
        "name": "conversations_add_message",
        "arguments": args
    })
    return client.wait_for_response(req_id)

def main():
    print("=" * 60)
    print("Agent Event Bus - Comprehensive E2E Test (Persistent Session)")
    print("=" * 60)
    
    client = MCPClient()
    
    # Initialize
    print("1. Initializing MCP Server...")
    req_id = client.send_request("initialize", {
        "protocolVersion": "2024-11-05", 
        "capabilities": {}, 
        "clientInfo": {"name": "e2e", "version": "1.0"}
    })
    resp = client.wait_for_response(req_id)
    if "result" in resp:
        print("   ✅ Initialized")
    else:
        print(f"   ❌ Init failed: {resp}")
        client.close()
        return 1

    # Wait for cache sync (just in case, though ID usage should bypass)
    print("   Waiting 5s for cache warmup...")
    time.sleep(5)
    
    passed = 0
    failed = 0
    
    # (name, event_type, payload, repo, beads_id)
    workflows = [
        ("Nightly Dispatcher", "DISPATCH_REQUEST", {"backend": "opencode:epyc6", "prompt": "Fix test"}, "prime-radiant-ai", "bd-e2e-001"),
        ("Jules Dispatch", "JULES_COMPLETE", {"status": "completed", "jules_session_id": "123456"}, "affordabot", "bd-e2e-002"),
        ("OpenCode Dispatch", "PR_CREATED", {"pr_url": "https://github.com/stars-end/prime-radiant-ai/pull/999", "pr_number": 999}, "prime-radiant-ai", "bd-e2e-001"),
        ("Code Review (Pass)", "REVIEW_COMPLETE", {"passed": True, "pr_number": 999, "review_run_url": "https://github.com/stars-end/prime-radiant-ai/actions/runs/111"}, "prime-radiant-ai", "bd-e2e-001"),
        ("Code Review (Fail)", "REVIEW_COMPLETE", {"passed": False, "pr_number": 998, "summary": "CI failed: test_api"}, "agent-skills", "bd-e2e-003")
    ]
    
    # Run simple event workflows
    for name, etype, payload, repo, beads_id in workflows:
        print(f"\nTesting: {name}")
        resp = post_event(client, name, etype, payload, repo=repo, beads_id=beads_id)
        
        if "result" in resp:
            content = resp["result"].get("content", [{}])[0].get("text", "")
            if "MsgID" in content:
                print(f"   ✅ PASSED: {etype} posted")
                passed += 1
            else:
                print(f"   ❌ FAILED: Unexpected response format: {content[:100]}")
                failed += 1
        else:
            err = resp.get("error", {}).get("message", "Unknown")
            print(f"   ❌ FAILED: {err}")
            failed += 1
        time.sleep(1)

    # Test HITL (Threaded)
    print(f"\nTesting: HITL OpenClawd (Threaded)")
    # 1. Post parent
    resp = post_event(client, "HITL Parent", "HITL_DISPATCH", {"req": "dispatch"})
    if "result" in resp:
        content = resp["result"].get("content", [{}])[0].get("text", "")
        # Parse MsgID/ThreadTS - CSV format: MsgID,UserID,...
        # MsgID is the TS for top-level messages
        try:
            lines = content.strip().split("\n")
            if len(lines) > 1:
                fields = lines[1].split(",")
                thread_ts = fields[0]
                print(f"   ✅ Parent posted (ts: {thread_ts})")
                
                # 2. Post reply
                resp2 = post_event(client, "HITL Reply", "STATUS_UPDATE", {"status": "running"}, thread_ts)
                if "result" in resp2:
                     print(f"   ✅ Reply posted in thread")
                     passed += 1
                else:
                    print(f"   ❌ Reply failed: {resp2}")
                    failed += 1
            else:
                print(f"   ❌ Parse failed: {content}")
                failed += 1
        except Exception as e:
            print(f"   ❌ Exception parsing: {e}")
            failed += 1
    else:
        print(f"   ❌ Parent failed: {resp}")
        failed += 1
        
    print("\n" + "="*60)
    print(f"RESULTS: {passed} passed, {failed} failed")
    client.close()
    sys.exit(1 if failed > 0 else 0)

if __name__ == "__main__":
    main()
