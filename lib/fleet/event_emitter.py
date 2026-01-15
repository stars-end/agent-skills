#!/usr/bin/env python3
"""
Event Emitter - Posts events to #fleet-events via Slack MCP.

This module provides a simple interface for emitting events to the Agent Event Bus.
Used by FleetDispatcher, GitHub Actions, and other producers.
"""

import json
import os
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

# Channel ID for #fleet-events
FLEET_EVENTS_CHANNEL_ID = os.environ.get("FLEET_EVENTS_CHANNEL_ID", "C0A8YU9JW06")

# Find slack-mcp-server binary
SLACK_MCP_BIN = os.path.expanduser("~/go/bin/slack-mcp-server")
if not os.path.exists(SLACK_MCP_BIN):
    # Try linuxbrew path
    SLACK_MCP_BIN = "/home/linuxbrew/.linuxbrew/bin/slack-mcp-server"
if not os.path.exists(SLACK_MCP_BIN):
    SLACK_MCP_BIN = "slack-mcp-server"  # Hope it's in PATH


class EventEmitter:
    """Emits events to #fleet-events via Slack MCP server."""
    
    def __init__(self, sender: str = None):
        """Initialize emitter with sender identity."""
        self.sender = sender or self._get_sender_identity()
        
    def _get_sender_identity(self) -> str:
        """Build sender identity from environment."""
        hostname = os.uname().nodename.split('.')[0]
        user = os.environ.get("USER", "unknown")
        return f"{user}@{hostname}"
        
    def emit(
        self,
        event_type: str,
        repo: str,
        beads_id: str,
        payload: dict = None,
        correlation_id: str = None,
        causation_id: str = None,
        thread_ts: str = None,
    ) -> Optional[str]:
        """
        Emit an event to #fleet-events.
        
        Args:
            event_type: Type of event (DISPATCH_REQUEST, PR_CREATED, etc.)
            repo: Repository name
            beads_id: Beads issue ID
            payload: Event-specific data
            correlation_id: ID linking related events
            causation_id: ID of event that caused this one
            thread_ts: Slack thread timestamp to reply to
            
        Returns:
            Message timestamp if successful, None otherwise.
        """
        event_id = f"evt_{int(time.time())}_{event_type.lower()[:8]}"
        
        event = {
            "event_id": event_id,
            "event_type": event_type,
            "version": "1.0",
            "repo": repo,
            "beads_id": beads_id,
            "sender": self.sender,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "payload": payload or {}
        }
        
        if correlation_id:
            event["correlation_id"] = correlation_id
        if causation_id:
            event["causation_id"] = causation_id
            
        return self._post_to_slack(json.dumps(event), thread_ts)
        
    def _post_to_slack(self, message: str, thread_ts: str = None) -> Optional[str]:
        """Post message to Slack via MCP server."""
        args = {
            "channel_id": FLEET_EVENTS_CHANNEL_ID,
            "content_type": "text/plain",
            "payload": message
        }
        if thread_ts:
            args["thread_ts"] = thread_ts
            
        requests = [
            {"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "event-emitter", "version": "1.0"}
            }},
            {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {
                "name": "conversations_add_message",
                "arguments": args
            }}
        ]
        
        input_data = "\n".join(json.dumps(r) for r in requests)
        
        try:
            proc = subprocess.run(
                [SLACK_MCP_BIN, "--transport", "stdio"],
                input=input_data,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            # Parse response to get message timestamp
            for line in proc.stdout.split("\n"):
                if '"id":1' in line and '"result"' in line:
                    data = json.loads(line)
                    content = data.get("result", {}).get("content", [{}])[0].get("text", "")
                    # Parse MsgID from CSV response
                    lines = content.strip().split("\n")
                    if len(lines) > 1:
                        fields = lines[1].split(",")
                        return fields[0] if fields else None
        except Exception as e:
            print(f"EventEmitter error: {e}")
            
        return None


# Convenience function for quick emission
def emit_event(
    event_type: str,
    repo: str,
    beads_id: str,
    payload: dict = None,
    **kwargs
) -> Optional[str]:
    """Quick function to emit an event without creating an emitter instance."""
    emitter = EventEmitter()
    return emitter.emit(event_type, repo, beads_id, payload, **kwargs)
