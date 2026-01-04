#!/usr/bin/env python3
"""
slack-coordinator.py - Multi-Agent Slack Coordinator

Bridges Slack events to OpenCode servers via Socket Mode.
Routes tasks to appropriate agents based on channel and mentions.

Usage:
    python slack-coordinator.py

Environment Variables:
    SLACK_BOT_TOKEN    - Bot token (xoxb-...)
    SLACK_APP_TOKEN    - App-level token for Socket Mode (xapp-...)
    OPENCODE_URL       - OpenCode server URL (default: http://localhost:4105)
"""

import os
import json
import asyncio
import logging
import re
from typing import Dict, Optional
from datetime import datetime

# Slack SDK
from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

# HTTP client for OpenCode
import httpx

# Configuration
OPENCODE_URL = os.environ.get("OPENCODE_URL", "http://localhost:4105")
AGENT_NAME = os.environ.get("AGENT_NAME", "Epyc-Primary")
MAX_SESSIONS = 10
SESSION_TIMEOUT_MIN = 30

# Logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("slack-coordinator")

# Channel to repo mapping
CHANNEL_REPO_MAP = {
    "affordabot-agents": "affordabot",
    "prime-radiant-agents": "prime-radiant-ai",
    "agent-coordination": None,  # Cross-repo
}

# Session registry
active_sessions: Dict[str, dict] = {}

# Initialize Slack app
app = App(token=os.environ.get("SLACK_BOT_TOKEN"))


def format_agent_message(message: str) -> str:
    """Format message with agent identity."""
    return f"[{AGENT_NAME}] {message}"


# Jules Integration (Three-Gate Routing)
JULES_DISPATCH_SCRIPT = "/home/feng/agent-skills/jules-dispatch/dispatch.py"


def should_route_to_jules(text: str, issue_id: Optional[str]) -> bool:
    """
    Check if task should be routed to Jules (cloud agent).
    Requires ALL three conditions:
    1. @jules mention in text
    2. jules-ready label on Beads issue
    3. docs/bd-xxxx/ spec file exists
    """
    import subprocess
    import os
    
    # Gate 1: @jules mention
    if "@jules" not in text.lower():
        return False
    
    if not issue_id:
        return False
    
    # Gate 2: Check for jules-ready label in Beads
    try:
        result = subprocess.run(
            ["bd", "show", issue_id, "--json"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            return False
        
        import json
        issue = json.loads(result.stdout)
        labels = issue.get("labels", [])
        if "jules-ready" not in labels:
            return False
    except Exception:
        return False
    
    # Gate 3: Check for docs/bd-xxxx/ spec directory
    # Check in likely repo locations
    for repo in ["/home/feng/affordabot", "/home/feng/prime-radiant-ai"]:
        spec_path = os.path.join(repo, "docs", issue_id)
        if os.path.isdir(spec_path):
            return True
    
    return False


async def dispatch_to_jules(issue_id: str, repo: str) -> Optional[str]:
    """Dispatch task to Jules using existing skill."""
    import subprocess
    
    try:
        result = subprocess.run(
            ["python3", JULES_DISPATCH_SCRIPT, issue_id, "--repo", repo],
            capture_output=True, text=True, timeout=30,
            cwd=f"/home/feng/{repo}"
        )
        if result.returncode == 0:
            return result.stdout
        else:
            logger.error(f"Jules dispatch failed: {result.stderr}")
            return None
    except Exception as e:
        logger.error(f"Jules dispatch error: {e}")
        return None


async def check_opencode_health() -> bool:
    """Check if OpenCode server is healthy."""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{OPENCODE_URL}/global/health", timeout=5)
            data = response.json()
            return data.get("healthy", False)
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return False


# Human-in-the-Loop Approval Workflow
APPROVAL_BACKOFFS = [30, 60, 120, 240, 480, 960]  # seconds
APPROVAL_TIMEOUT_MIN = 60


async def wait_for_approval(client, channel_id: str, thread_ts: str) -> str:
    """
    Wait for human approval with exponential backoff polling.
    Returns: 'approved', 'rejected', or 'timeout'
    """
    elapsed = 0
    
    for delay in APPROVAL_BACKOFFS:
        await asyncio.sleep(delay)
        elapsed += delay
        
        if elapsed > APPROVAL_TIMEOUT_MIN * 60:
            return "timeout"
        
        try:
            # Get thread replies
            response = client.conversations_replies(
                channel=channel_id,
                ts=thread_ts,
                limit=20
            )
            
            messages = response.get("messages", [])
            for msg in messages:
                text = msg.get("text", "").lower()
                # Skip bot messages
                if msg.get("bot_id"):
                    continue
                
                if "approve" in text or "approved" in text or "lgtm" in text or "yes" in text:
                    return "approved"
                if "reject" in text or "rejected" in text or "no" in text:
                    return "rejected"
        
        except Exception as e:
            logger.error(f"Failed to check replies: {e}")
    
    return "timeout"


async def request_approval(say, thread_ts: str, message: str) -> None:
    """Post an approval request to Slack."""
    say(
        format_agent_message(f"🔒 **Approval Required**\n{message}\n\nReply with `approve` or `reject`"),
        thread_ts=thread_ts
    )


async def get_session_count() -> int:
    """Get current active session count."""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{OPENCODE_URL}/session", timeout=5)
            sessions = response.json()
            return len(sessions)
    except Exception as e:
        logger.error(f"Failed to get session count: {e}")
        return 0


async def create_opencode_session(title: str) -> Optional[str]:
    """Create a new OpenCode session."""
    try:
        # Check session limit
        count = await get_session_count()
        if count >= MAX_SESSIONS:
            logger.warning(f"Session limit reached ({count}/{MAX_SESSIONS})")
            return None
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{OPENCODE_URL}/session",
                json={"title": title},
                timeout=10
            )
            data = response.json()
            return data.get("id")
    except Exception as e:
        logger.error(f"Failed to create session: {e}")
        return None


async def send_to_opencode(session_id: str, prompt: str) -> Optional[dict]:
    """Send a prompt to OpenCode session."""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{OPENCODE_URL}/session/{session_id}/message",
                json={"parts": [{"type": "text", "text": prompt}]},
                timeout=120  # 2 minutes for complex tasks
            )
            return response.json()
    except Exception as e:
        logger.error(f"Failed to send to OpenCode: {e}")
        return None


def should_respond(message: dict, channel_name: str) -> bool:
    """Determine if agent should respond to this message."""
    text = message.get("text", "").lower()
    
    # Direct mention
    if f"@{AGENT_NAME.lower()}" in text:
        return True
    
    # Generic task in monitored channel
    if channel_name in CHANNEL_REPO_MAP:
        if "[task]" in text:
            return True
    
    return False


def extract_task_info(text: str) -> dict:
    """Extract task information from message text."""
    info = {"raw": text}
    
    # Extract issue ID (bd-xxx format)
    issue_match = re.search(r"\b(bd-\w+)\b", text, re.IGNORECASE)
    if issue_match:
        info["issue_id"] = issue_match.group(1)
    
    # Extract repo if specified
    repo_match = re.search(r"repo:(\w+)", text, re.IGNORECASE)
    if repo_match:
        info["repo"] = repo_match.group(1)
    
    return info


@app.event("message")
def handle_message(event, say, client):
    """Handle incoming Slack messages."""
    # Skip bot messages
    if event.get("bot_id"):
        return
    
    # Get channel info
    channel_id = event.get("channel")
    channel_info = client.conversations_info(channel=channel_id)
    channel_name = channel_info.get("channel", {}).get("name", "")
    
    # Check if we should respond
    if not should_respond(event, channel_name):
        return
    
    logger.info(f"Received task in #{channel_name}: {event.get('text', '')[:100]}")
    
    # Extract task info
    task_info = extract_task_info(event.get("text", ""))
    
    # Create session and process
    asyncio.run(process_task(event, say, channel_name, task_info))


async def process_task(event: dict, say, channel_name: str, task_info: dict):
    """Process a task from Slack."""
    thread_ts = event.get("thread_ts") or event.get("ts")
    
    # Acknowledge
    say(
        format_agent_message(f"Received task. Processing..."),
        thread_ts=thread_ts
    )
    
    # Create session
    issue_id = task_info.get("issue_id", "unknown")
    session_title = f"{AGENT_NAME}: {issue_id}"
    session_id = await create_opencode_session(session_title)
    
    if not session_id:
        say(
            format_agent_message("❌ Failed to create session (limit reached or error)"),
            thread_ts=thread_ts
        )
        return
    
    # Track session
    active_sessions[session_id] = {
        "thread_ts": thread_ts,
        "channel": event.get("channel"),
        "issue_id": issue_id,
        "started": datetime.now().isoformat()
    }
    
    # Build prompt
    repo = task_info.get("repo") or CHANNEL_REPO_MAP.get(channel_name)
    prompt = f"""
Task from Slack #{channel_name}
Issue ID: {issue_id}
Repo: {repo or 'Not specified'}

Original message:
{task_info['raw']}

Instructions:
1. Analyze the task
2. If repo specified, work in that context
3. Report progress
4. Return a summary when done
"""
    
    # Send to OpenCode
    say(
        format_agent_message(f"⚙️ Working on task (session: {session_id[:12]}...)"),
        thread_ts=thread_ts
    )
    
    result = await send_to_opencode(session_id, prompt)
    
    if result:
        # Extract response text
        parts = result.get("parts", [])
        response_text = ""
        for part in parts:
            if part.get("type") == "text":
                response_text = part.get("text", "")
                break
        
        # Post result (truncate if too long)
        if len(response_text) > 1500:
            response_text = response_text[:1500] + "...(truncated)"
        
        say(
            format_agent_message(f"✅ Task complete:\n{response_text}"),
            thread_ts=thread_ts
        )
    else:
        say(
            format_agent_message("❌ Task failed - no response from OpenCode"),
            thread_ts=thread_ts
        )
    
    # Cleanup session tracking
    active_sessions.pop(session_id, None)


@app.event("app_mention")
def handle_mention(event, say, client):
    """Handle direct mentions of the bot."""
    handle_message(event, say, client)


def main():
    """Main entry point."""
    logger.info(f"Starting {AGENT_NAME} Slack Coordinator")
    logger.info(f"OpenCode URL: {OPENCODE_URL}")
    
    # Verify environment
    if not os.environ.get("SLACK_BOT_TOKEN"):
        logger.error("SLACK_BOT_TOKEN not set")
        return
    if not os.environ.get("SLACK_APP_TOKEN"):
        logger.error("SLACK_APP_TOKEN not set")
        return
    
    # Check OpenCode health
    if not asyncio.run(check_opencode_health()):
        logger.warning("OpenCode server not healthy, coordinator will retry on messages")
    
    # Start Socket Mode handler
    handler = SocketModeHandler(app, os.environ["SLACK_APP_TOKEN"])
    logger.info("Starting Socket Mode handler...")
    handler.start()


if __name__ == "__main__":
    main()
