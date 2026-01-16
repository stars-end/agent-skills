#!/usr/bin/env python3
"""
Fleet Controller - Agent Event Bus V0.5

Single-writer daemon that:
1. Consumes events from Slack #fleet-events via MCP
2. Polls OpenCode/Jules for session completion
3. Tracks state transitions (local JSON for V0.5)
4. Posts notifications to Slack threads
"""

import json
import os
import subprocess
import threading
import time
from dataclasses import dataclass, asdict, field
from datetime import datetime
from pathlib import Path
from typing import Optional

# Channel ID for #fleet-events (use ID to bypass cache issues)
FLEET_EVENTS_CHANNEL_ID = os.environ.get("FLEET_EVENTS_CHANNEL_ID", "C0A8YU9JW06")
# Use absolute path - falls back to PATH if not found
SLACK_MCP_BIN = os.path.expanduser("~/go/bin/slack-mcp-server")
if not os.path.exists(SLACK_MCP_BIN):
    SLACK_MCP_BIN = "slack-mcp-server"  # Hope it's in PATH
SLACK_MCP_CMD = [SLACK_MCP_BIN, "--transport", "stdio"]
CONTROLLER_STATE_PATH = Path.home() / ".fleet-controller" / "state.json"
DISPATCH_STATE_PATH = Path.home() / ".fleet-controller" / "dispatches.json"
POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL_SECONDS", "60"))
MAX_RETRIES = 2



@dataclass
class DispatchState:
    """State record for a single dispatch."""
    repo: str
    beads_id: str
    backend: str  # opencode:epyc6 | opencode:macmini | jules
    session_id: str
    jules_session_id: Optional[str] = None
    status: str = "requested"  # requested|running|pr_created|review_pending|review_failed|retrying|done|escalated|error
    retry_count: int = 0
    pr_url: Optional[str] = None
    review_run_url: Optional[str] = None
    last_error: Optional[str] = None
    last_event_id: Optional[str] = None
    slack_channel_id: Optional[str] = None
    slack_thread_ts: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


@dataclass
class ControllerState:
    """Controller cursor and dedupe state."""
    last_seen_ts: str = "0"
    processed_event_ids: list = field(default_factory=list)


class SlackMCPClient:
    """Client for Slack MCP server (persistent session)."""
    
    def __init__(self):
        self.proc = None
        self.responses = {}
        self.response_lock = threading.Lock()
        self.running = False
        self.reader_thread = None
        
    def start(self):
        """Start the MCP server process."""
        self.proc = subprocess.Popen(
            SLACK_MCP_CMD,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1
        )
        self.running = True
        self.reader_thread = threading.Thread(target=self._read_stdout, daemon=True)
        self.reader_thread.start()
        
        # Initialize
        self._send_request("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "fleet-controller", "version": "0.5"}
        }, req_id=0)
        time.sleep(2)  # Wait for init
        
    def _read_stdout(self):
        while self.running and self.proc:
            try:
                line = self.proc.stdout.readline()
                if not line:
                    break
                line = line.strip()
                if line.startswith('{"jsonrpc"'):
                    try:
                        data = json.loads(line)
                        if "id" in data:
                            with self.response_lock:
                                self.responses[data["id"]] = data
                    except:
                        pass
            except:
                break
                
    def _send_request(self, method: str, params: dict = None, req_id: int = None) -> int:
        if req_id is None:
            req_id = int(time.time() * 1000) % 1000000
        req = {"jsonrpc": "2.0", "id": req_id, "method": method}
        if params:
            req["params"] = params
        try:
            self.proc.stdin.write(json.dumps(req) + "\n")
            self.proc.stdin.flush()
        except:
            pass
        return req_id
        
    def _wait_response(self, req_id: int, timeout: float = 15) -> dict:
        start = time.time()
        while time.time() - start < timeout:
            with self.response_lock:
                if req_id in self.responses:
                    return self.responses.pop(req_id)
            time.sleep(0.1)
        return {"error": {"message": "Timeout"}}
        
    def get_channel_history(self, channel_id: str, oldest_ts: str = None, limit: int = 50) -> list:
        """Fetch messages from a channel."""
        args = {"channel_id": channel_id, "limit": str(limit)}
        req_id = self._send_request("tools/call", {
            "name": "conversations_history",
            "arguments": args
        })
        resp = self._wait_response(req_id)
        if "result" in resp:
            content = resp["result"].get("content", [{}])[0].get("text", "")
            return self._parse_csv_messages(content, oldest_ts)
        return []
        
    def _parse_csv_messages(self, csv_content: str, oldest_ts: str = None) -> list:
        """Parse CSV message response into list of dicts."""
        import csv
        import io
        
        messages = []
        reader = csv.DictReader(io.StringIO(csv_content))
        
        for row in reader:
            msg_id = row.get("MsgID", "0")
            # Filter by oldest_ts
            if oldest_ts and msg_id <= oldest_ts:
                continue
            messages.append(row)
            
        return messages

        
    def post_message(self, channel_id: str, text: str, thread_ts: str = None) -> bool:
        """Post a message to a channel."""
        args = {
            "channel_id": channel_id,
            "content_type": "text/plain",
            "payload": text
        }
        if thread_ts:
            args["thread_ts"] = thread_ts
        req_id = self._send_request("tools/call", {
            "name": "conversations_add_message",
            "arguments": args
        })
        resp = self._wait_response(req_id)
        return "result" in resp
        
    def stop(self):
        self.running = False
        if self.proc:
            self.proc.terminate()


class FleetController:
    """Main controller daemon."""
    
    def __init__(self):
        self.state = self._load_controller_state()
        self.dispatches = self._load_dispatch_states()
        self.slack = None
        
    def _load_controller_state(self) -> ControllerState:
        if CONTROLLER_STATE_PATH.exists():
            data = json.loads(CONTROLLER_STATE_PATH.read_text())
            return ControllerState(**data)
        return ControllerState()
        
    def _save_controller_state(self):
        CONTROLLER_STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
        CONTROLLER_STATE_PATH.write_text(json.dumps(asdict(self.state), indent=2))
        
    def _load_dispatch_states(self) -> dict:
        """Load dispatch states keyed by (repo, beads_id)."""
        if DISPATCH_STATE_PATH.exists():
            data = json.loads(DISPATCH_STATE_PATH.read_text())
            return {k: DispatchState(**v) for k, v in data.items()}
        return {}
        
    def _save_dispatch_states(self):
        DISPATCH_STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
        data = {k: asdict(v) for k, v in self.dispatches.items()}
        DISPATCH_STATE_PATH.write_text(json.dumps(data, indent=2))
        
    def _dispatch_key(self, repo: str, beads_id: str) -> str:
        return f"{repo}:{beads_id}"
        
    def poll_slack_events(self) -> list:
        """Fetch new events from #fleet-events."""
        messages = self.slack.get_channel_history(
            FLEET_EVENTS_CHANNEL_ID, 
            oldest_ts=self.state.last_seen_ts
        )
        return messages
        
    def dedupe_event(self, event_id: str) -> bool:
        """Return True if event is new, False if duplicate."""
        if event_id in self.state.processed_event_ids:
            return False
        self.state.processed_event_ids.append(event_id)
        if len(self.state.processed_event_ids) > 1000:
            self.state.processed_event_ids = self.state.processed_event_ids[-500:]
        return True
        
    def parse_event(self, message: dict) -> dict:
        """Parse a Slack message into an event dict.
        
        Slack transforms JSON like {"event_id": "x", "event_type": "Y"} into
        display format: "event_id: x, event_type: Y", so we need to parse both.
        """
        text = message.get("Text", "")
        msg_id = message.get("MsgID", "")
        
        # Debug: show what we're trying to parse
        print(f"    Parsing msg {msg_id}: {text[:80]}...")
        
        # Try 1: Direct JSON parse (for code-block wrapped or already-JSON)
        try:
            if text.strip().startswith("{"):
                event = json.loads(text)
                event["_slack_ts"] = msg_id
                event["_slack_channel"] = FLEET_EVENTS_CHANNEL_ID
                print(f"    ✓ Parsed as JSON: event_type={event.get('event_type')}")
                return event
        except json.JSONDecodeError:
            pass
        
        # Try 2: Parse Slack's key: value format
        # Format: "event_id: evt_xxx, event_type: DISPATCH_REQUEST, version: 1.0, ..."
        if "event_type:" in text and "event_id:" in text:
            try:
                event = {}
                # Split on ", " but be careful with nested values
                parts = text.split(", ")
                for part in parts:
                    if ":" in part:
                        key, _, val = part.partition(":")
                        key = key.strip()
                        val = val.strip()
                        # Handle nested payload
                        if key == "payload":
                            # Payload might have nested key: value
                            event[key] = {"raw": val}
                        else:
                            event[key] = val
                            
                if "event_type" in event:
                    event["_slack_ts"] = msg_id
                    event["_slack_channel"] = FLEET_EVENTS_CHANNEL_ID
                    print(f"    ✓ Parsed as key:value: event_type={event.get('event_type')}, event_id={event.get('event_id')}")
                    return event
            except Exception as e:
                print(f"    ✗ key:value parse error: {e}")
        
        print(f"    ✗ Not an event message")
        return None


            
    def transition_state(self, repo: str, beads_id: str, new_status: str, **updates):
        """Update dispatch state and notify."""
        key = self._dispatch_key(repo, beads_id)
        
        if key not in self.dispatches:
            # Create new
            self.dispatches[key] = DispatchState(
                repo=repo,
                beads_id=beads_id,
                backend=updates.get("backend", "unknown"),
                session_id=updates.get("session_id", ""),
                created_at=datetime.utcnow().isoformat() + "Z"
            )
            
        dispatch = self.dispatches[key]
        old_status = dispatch.status
        dispatch.status = new_status
        dispatch.updated_at = datetime.utcnow().isoformat() + "Z"
        
        # Apply updates
        for k, v in updates.items():
            if hasattr(dispatch, k):
                setattr(dispatch, k, v)
                
        self._save_dispatch_states()
        print(f"  [{repo}/{beads_id}] {old_status} → {new_status}")
        
        # Post to Slack thread if available
        if dispatch.slack_thread_ts:
            self.slack.post_message(
                dispatch.slack_channel_id or FLEET_EVENTS_CHANNEL_ID,
                f"[{beads_id}] Status: {new_status}",
                thread_ts=dispatch.slack_thread_ts
            )
            
    def process_event(self, event: dict):
        """Process a single event."""
        event_type = event.get("event_type")
        repo = event.get("repo", "")
        beads_id = event.get("beads_id", "")
        payload = event.get("payload", {})
        
        print(f"  Processing: {event_type} for {repo}/{beads_id}")
        
        if event_type == "DISPATCH_REQUEST":
            self.transition_state(repo, beads_id, "running",
                backend=payload.get("backend", "unknown"),
                session_id=payload.get("session_id", ""),
                slack_channel_id=event.get("_slack_channel"),
                slack_thread_ts=event.get("_slack_ts"))
                
        elif event_type == "JULES_COMPLETE":
            self.transition_state(repo, beads_id, "pr_created",
                jules_session_id=payload.get("jules_session_id"),
                pr_url=payload.get("pr_url"))
                
        elif event_type == "PR_CREATED":
            self.transition_state(repo, beads_id, "review_pending",
                pr_url=payload.get("pr_url"),
                session_id=payload.get("session_id"))
                
        elif event_type == "REVIEW_COMPLETE":
            passed = payload.get("passed", False)
            if passed:
                self.transition_state(repo, beads_id, "done",
                    review_run_url=payload.get("review_run_url"))
            else:
                key = self._dispatch_key(repo, beads_id)
                dispatch = self.dispatches.get(key)
                retry_count = (dispatch.retry_count if dispatch else 0) + 1
                
                if retry_count >= MAX_RETRIES:
                    self.transition_state(repo, beads_id, "escalated",
                        last_error=payload.get("summary"),
                        review_run_url=payload.get("review_run_url"),
                        retry_count=retry_count)
                else:
                    self.transition_state(repo, beads_id, "review_failed",
                        last_error=payload.get("summary"),
                        review_run_url=payload.get("review_run_url"),
                        retry_count=retry_count)
                        
        elif event_type == "STATUS_UPDATE":
            # Just a thread update, no state change
            pass
            
    def get_status(self, repo: str, beads_id: str) -> Optional[DispatchState]:
        """Get current status of a dispatch."""
        key = self._dispatch_key(repo, beads_id)
        return self.dispatches.get(key)
        
    def explain(self, beads_id: str) -> str:
        """Generate explain view for a beads_id."""
        for key, dispatch in self.dispatches.items():
            if dispatch.beads_id == beads_id:
                lines = [
                    f"{dispatch.beads_id} ({dispatch.repo})",
                    f"Status: {dispatch.status}" + (f" (retry {dispatch.retry_count}/{MAX_RETRIES})" if dispatch.retry_count else ""),
                ]
                if dispatch.pr_url:
                    lines.append(f"PR: {dispatch.pr_url}")
                if dispatch.review_run_url:
                    lines.append(f"Review: {dispatch.review_run_url}")
                if dispatch.session_id:
                    lines.append(f"Session: {dispatch.session_id}")
                if dispatch.last_error:
                    lines.append(f"Error: {dispatch.last_error}")
                return "\n".join(lines)
        return f"No dispatch found for {beads_id}"
        
    def run(self, once: bool = False):
        """Main control loop."""
        print(f"Fleet Controller starting (poll every {POLL_INTERVAL_SECONDS}s)")
        print(f"Channel: {FLEET_EVENTS_CHANNEL_ID}")
        
        self.slack = SlackMCPClient()
        self.slack.start()
        
        try:
            while True:
                try:
                    print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Polling...")
                    
                    # 1. Consume Slack events
                    messages = self.poll_slack_events()
                    print(f"  Found {len(messages)} new messages")
                    
                    for msg in messages:
                        event = self.parse_event(msg)
                        if event and self.dedupe_event(event.get("event_id", msg.get("MsgID"))):
                            self.process_event(event)
                        # Update cursor
                        ts = msg.get("MsgID", "0")
                        if ts > self.state.last_seen_ts:
                            self.state.last_seen_ts = ts
                            
                    # 2. Save state
                    self._save_controller_state()
                    
                    if once:
                        break
                        
                except Exception as e:
                    print(f"  Error: {e}")
                    import traceback
                    traceback.print_exc()
                    
                time.sleep(POLL_INTERVAL_SECONDS)
                
        finally:
            self.slack.stop()


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Fleet Controller")
    parser.add_argument("--once", action="store_true", help="Run one poll cycle and exit")
    parser.add_argument("--explain", metavar="BD_ID", help="Explain status for beads_id")
    args = parser.parse_args()
    
    controller = FleetController()
    
    if args.explain:
        print(controller.explain(args.explain))
    else:
        controller.run(once=args.once)


if __name__ == "__main__":
    main()
