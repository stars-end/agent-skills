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
    AGENT_NAME         - Agent identity for responses (default: epyc6)
"""

import os
import json
import asyncio
import logging
import re
import subprocess
from pathlib import Path
from typing import Dict, Optional, Tuple
from datetime import datetime

# Slack SDK
from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

# HTTP client for OpenCode
import httpx

# Configuration
LOCAL_OPENCODE_URL = os.environ.get("OPENCODE_URL", "http://localhost:4105")
AGENT_NAME = os.environ.get("AGENT_NAME", "epyc6")
MAX_SESSIONS = 10
SESSION_TIMEOUT_MIN = 30

# Multi-VM Routing (P1)
VM_ENDPOINTS = {
    "epyc6": LOCAL_OPENCODE_URL,
    "macmini": "http://macmini.tail76761.ts.net:4105",  # Tailscale hostname
}
DEFAULT_VM = "epyc6"

# Worktree Configuration (P0)
WORKTREE_BASE = Path.home()
REPOS = {
    "affordabot": Path.home() / "affordabot",
    "prime-radiant-ai": Path.home() / "prime-radiant-ai",
    "agent-skills": Path.home() / "agent-skills",
}

# Logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("slack-coordinator")

# Channel to repo mapping
CHANNEL_REPO_MAP = {
    "affordabot-agents": "affordabot",
    "prime-radiant-agents": "prime-radiant-ai",
    "agent-coordination": None,  # Cross-repo
}

# Session registry (in-memory, thread_ts -> session info)
active_sessions: Dict[str, dict] = {}

# Initialize Slack app
app = App(token=os.environ.get("SLACK_BOT_TOKEN"))


# =============================================================================
# P0: Worktree Management
# =============================================================================

def ensure_worktree(repo_name: str, issue_id: str) -> Optional[str]:
    """
    Create or return path to worktree for a Beads issue.
    
    Args:
        repo_name: Name of repo (e.g., 'affordabot')
        issue_id: Beads issue ID (e.g., 'bd-xyz')
    
    Returns:
        Path to worktree directory, or None on failure
    """
    if repo_name not in REPOS:
        logger.error(f"Unknown repo: {repo_name}")
        return None
    
    repo_path = REPOS[repo_name]
    worktree_root = WORKTREE_BASE / f"{repo_name}-worktrees"
    worktree_path = worktree_root / issue_id
    
    # Create worktree root if needed
    worktree_root.mkdir(parents=True, exist_ok=True)
    
    if worktree_path.exists():
        logger.info(f"Worktree exists: {worktree_path}")
        return str(worktree_path)
    
    try:
        # Create branch and worktree
        branch_name = f"feature-{issue_id}"
        
        # First, try to create worktree with new branch
        result = subprocess.run(
            ["git", "worktree", "add", str(worktree_path), "-b", branch_name],
            cwd=str(repo_path),
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode != 0:
            # Branch might exist, try without -b
            result = subprocess.run(
                ["git", "worktree", "add", str(worktree_path), branch_name],
                cwd=str(repo_path),
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode != 0:
                # Create from HEAD
                result = subprocess.run(
                    ["git", "worktree", "add", str(worktree_path)],
                    cwd=str(repo_path),
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                
                if result.returncode != 0:
                    logger.error(f"Failed to create worktree: {result.stderr}")
                    return None
        
        logger.info(f"Created worktree: {worktree_path}")
        return str(worktree_path)
        
    except subprocess.TimeoutExpired:
        logger.error(f"Worktree creation timed out for {issue_id}")
        return None
    except Exception as e:
        logger.error(f"Worktree creation error: {e}")
        return None


def cleanup_worktree(repo_name: str, issue_id: str) -> bool:
    """Remove a worktree after issue completion."""
    if repo_name not in REPOS:
        return False
    
    repo_path = REPOS[repo_name]
    worktree_path = WORKTREE_BASE / f"{repo_name}-worktrees" / issue_id
    
    if not worktree_path.exists():
        return True
    
    try:
        result = subprocess.run(
            ["git", "worktree", "remove", str(worktree_path)],
            cwd=str(repo_path),
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.returncode == 0
    except Exception as e:
        logger.error(f"Worktree cleanup error: {e}")
        return False


# =============================================================================
# P1: Multi-VM Routing
# =============================================================================

def parse_target_vm(text: str) -> str:
    """
    Parse target VM from message text.
    
    @macmini -> macmini
    @epyc6 -> epyc6
    (no mention) -> default (epyc6)
    """
    text_lower = text.lower()
    
    if "@macmini" in text_lower:
        return "macmini"
    elif "@epyc6" in text_lower:
        return "epyc6"
    else:
        return DEFAULT_VM


def get_opencode_url(vm: str) -> str:
    """Get OpenCode URL for a VM."""
    return VM_ENDPOINTS.get(vm, LOCAL_OPENCODE_URL)


def parse_session_resume(text: str) -> Optional[str]:
    """Extract session ID for resume from text."""
    match = re.search(r"session:(\S+)", text, re.IGNORECASE)
    if match:
        return match.group(1)
    return None


# =============================================================================
# Agent Identity
# =============================================================================

def format_agent_message(message: str, vm: str = None) -> str:
    """Format message with agent identity."""
    identity = vm or AGENT_NAME
    return f"[{identity}] {message}"


# Jules Integration (Three-Gate Routing)
JULES_DISPATCH_SCRIPT = str(Path.home() / "agent-skills" / "jules-dispatch" / "dispatch.py")


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
    for repo_name in ["affordabot", "prime-radiant-ai"]:
        spec_path = Path.home() / repo_name / "docs" / issue_id
        if spec_path.is_dir():
            return True
    
    return False


async def dispatch_to_jules(issue_id: str, repo: str) -> Optional[str]:
    """Dispatch task to Jules using existing skill."""
    import subprocess
    
    try:
        result = subprocess.run(
            ["python3", JULES_DISPATCH_SCRIPT, issue_id, "--repo", repo],
            capture_output=True, text=True, timeout=30,
            cwd=str(Path.home() / repo)
        )
        if result.returncode == 0:
            return result.stdout
        else:
            logger.error(f"Jules dispatch failed: {result.stderr}")
            return None
    except Exception as e:
        logger.error(f"Jules dispatch error: {e}")
        return None


async def check_opencode_health(vm: str = None) -> bool:
    """Check if OpenCode server is healthy."""
    url = get_opencode_url(vm) if vm else LOCAL_OPENCODE_URL
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{url}/global/health", timeout=5)
            data = response.json()
            return data.get("healthy", False)
    except Exception as e:
        logger.error(f"Health check failed for {vm or 'local'}: {e}")
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


async def get_session_count(vm: str = None) -> int:
    """Get current active session count."""
    url = get_opencode_url(vm) if vm else LOCAL_OPENCODE_URL
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{url}/session", timeout=5)
            sessions = response.json()
            return len(sessions)
    except Exception as e:
        logger.error(f"Failed to get session count for {vm or 'local'}: {e}")
        return 0


async def create_opencode_session(title: str, vm: str = None) -> Optional[str]:
    """Create a new OpenCode session on specified VM."""
    url = get_opencode_url(vm) if vm else LOCAL_OPENCODE_URL
    try:
        # Check session limit
        count = await get_session_count(vm)
        if count >= MAX_SESSIONS:
            logger.warning(f"Session limit reached on {vm or 'local'} ({count}/{MAX_SESSIONS})")
            return None
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{url}/session",
                json={"title": title},
                timeout=10
            )
            data = response.json()
            return data.get("id")
    except Exception as e:
        logger.error(f"Failed to create session on {vm or 'local'}: {e}")
        return None


async def send_to_opencode(session_id: str, prompt: str, vm: str = None) -> Optional[dict]:
    """Send a prompt to OpenCode session on specified VM."""
    url = get_opencode_url(vm) if vm else LOCAL_OPENCODE_URL
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{url}/session/{session_id}/message",
                json={"parts": [{"type": "text", "text": prompt}]},
                timeout=300  # 5 minutes for complex tasks
            )
            return response.json()
    except Exception as e:
        logger.error(f"Failed to send to OpenCode on {vm or 'local'}: {e}")
        return None


def should_respond(message: dict, channel_name: str) -> bool:
    """
    Determine if this coordinator should respond to this message.
    Responds if:
    - Direct mention of this agent (@epyc6)
    - Any VM mention (@macmini, @epyc6) in monitored channel
    - [TASK] prefix in monitored channel
    - Thread reply with @mention for handoff
    """
    text = message.get("text", "").lower()
    
    # Check for any VM mention (for routing)
    for vm in VM_ENDPOINTS.keys():
        if f"@{vm}" in text:
            return True
    
    # Direct mention of this agent
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
    """
    Process a task from Slack with full P0+P1 support:
    - P0: Worktree creation per issue
    - P1: Multi-VM routing based on @mention
    """
    text = event.get("text", "")
    thread_ts = event.get("thread_ts") or event.get("ts")
    
    # P1: Determine target VM from @mention
    target_vm = parse_target_vm(text)
    
    # P0: Extract issue ID and determine repo
    issue_id = task_info.get("issue_id", "unknown")
    repo = task_info.get("repo") or CHANNEL_REPO_MAP.get(channel_name)
    
    # Acknowledge with correct VM identity
    say(
        format_agent_message(f"Received task. Routing to {target_vm}...", target_vm),
        thread_ts=thread_ts
    )
    
    # Check if this is a session resume
    resume_session_id = parse_session_resume(text)
    if resume_session_id:
        logger.info(f"Resuming session {resume_session_id} on {target_vm}")
        session_id = resume_session_id
    else:
        # Create new session on target VM
        session_title = f"{target_vm}: {issue_id}"
        session_id = await create_opencode_session(session_title, target_vm)
        
        if not session_id:
            say(
                format_agent_message(f"❌ Failed to create session on {target_vm}", target_vm),
                thread_ts=thread_ts
            )
            return
    
    # P0: Create worktree if repo and issue_id are known
    worktree_path = None
    if repo and issue_id != "unknown":
        worktree_path = ensure_worktree(repo, issue_id)
        if worktree_path:
            logger.info(f"Using worktree: {worktree_path}")
        else:
            logger.warning(f"Failed to create worktree for {issue_id} in {repo}")
    
    # Track session
    active_sessions[session_id] = {
        "thread_ts": thread_ts,
        "channel": event.get("channel"),
        "issue_id": issue_id,
        "repo": repo,
        "worktree": worktree_path,
        "target_vm": target_vm,
        "started": datetime.now().isoformat()
    }
    
    # Build prompt with worktree context
    cwd_instruction = ""
    if worktree_path:
        cwd_instruction = f"""
IMPORTANT: Working directory is: {worktree_path}
Before any file operations, run: cd {worktree_path}
Use BEADS_NO_DAEMON=1 for any bd commands.
"""
    
    prompt = f"""
Task from Slack #{channel_name}
Target VM: {target_vm}
Issue ID: {issue_id}
Repo: {repo or 'Not specified'}
{cwd_instruction}

Original message:
{task_info['raw']}

Instructions:
1. If worktree path provided, cd to it first
2. Analyze the task
3. Work in the repo context
4. Update Beads status as you progress
5. Return a summary when done

Remember:
- Use Feature-Key: {issue_id} in commits
- Use BEADS_NO_DAEMON=1 for bd commands in worktrees
"""
    
    # Send to OpenCode on target VM
    say(
        format_agent_message(f"⚙️ Working on {issue_id} (session: {session_id[:12]}...)", target_vm),
        thread_ts=thread_ts
    )
    
    result = await send_to_opencode(session_id, prompt, target_vm)
    
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
            format_agent_message(f"✅ Task complete:\n{response_text}", target_vm),
            thread_ts=thread_ts
        )
    else:
        say(
            format_agent_message(f"❌ Task failed - no response from OpenCode on {target_vm}", target_vm),
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
    logger.info(f"Local OpenCode URL: {LOCAL_OPENCODE_URL}")
    logger.info(f"VM Endpoints: {VM_ENDPOINTS}")
    logger.info(f"Worktree base: {WORKTREE_BASE}")
    
    # Verify environment
    if not os.environ.get("SLACK_BOT_TOKEN"):
        logger.error("SLACK_BOT_TOKEN not set")
        return
    if not os.environ.get("SLACK_APP_TOKEN"):
        logger.error("SLACK_APP_TOKEN not set")
        return
    
    # Check OpenCode health
    if not asyncio.run(check_opencode_health()):
        logger.warning("Local OpenCode server not healthy, coordinator will retry on messages")
    
    # Start Socket Mode handler
    handler = SocketModeHandler(app, os.environ["SLACK_APP_TOKEN"])
    logger.info("Starting Socket Mode handler...")
    handler.start()


if __name__ == "__main__":
    main()
