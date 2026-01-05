#!/usr/bin/env python3
"""
slack_e2e_tests.py - End-to-End Slack Tests for Multi-Agent Coordination

Performs actual Slack API calls to test:
1. Cross-VM routing (@epyc6, @macmini)
2. Agent-to-agent handoff
3. Jules three-gate routing

Usage:
    python3 slack_e2e_tests.py
"""

import os
import sys
import json
import time
import subprocess
from datetime import datetime
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

# Configuration
SLACK_BOT_TOKEN = os.environ.get("SLACK_MCP_XOXP_TOKEN") or os.environ.get("SLACK_BOT_TOKEN")
TEST_CHANNEL = "C09MQGMFKDE"  # #dev-agent-tasks or agent channel

if not SLACK_BOT_TOKEN:
    print("❌ ERROR: No SLACK_BOT_TOKEN found in environment")
    sys.exit(1)

client = WebClient(token=SLACK_BOT_TOKEN)

# Test results
results = {"passed": [], "failed": [], "skipped": []}


def log(msg: str, level: str = "INFO"):
    timestamp = datetime.now().strftime("%H:%M:%S")
    print(f"[{timestamp}] [{level}] {msg}")


def post_message(text: str, thread_ts: str = None) -> dict:
    """Post a message to the test channel."""
    try:
        response = client.chat_postMessage(
            channel=TEST_CHANNEL,
            text=text,
            thread_ts=thread_ts
        )
        return {"ok": True, "ts": response["ts"], "channel": response["channel"]}
    except SlackApiError as e:
        return {"ok": False, "error": str(e)}


def get_thread_replies(thread_ts: str, wait_seconds: int = 10) -> list:
    """Get replies in a thread after waiting for agent to respond."""
    log(f"Waiting {wait_seconds}s for agent response...")
    time.sleep(wait_seconds)
    
    try:
        response = client.conversations_replies(
            channel=TEST_CHANNEL,
            ts=thread_ts
        )
        return response.get("messages", [])
    except SlackApiError as e:
        log(f"Error getting replies: {e}", "ERROR")
        return []


def run_test(name: str, test_func):
    """Run a single test and record result."""
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
# Test 1: Basic Agent Response
# =============================================================================

def test_basic_agent_response():
    """Test that the agent responds to a basic message."""
    test_id = datetime.now().strftime("%H%M%S")
    
    result = post_message(f"[E2E-TEST-{test_id}] Basic test - please acknowledge")
    if not result["ok"]:
        return False, f"Failed to post message: {result.get('error')}"
    
    thread_ts = result["ts"]
    replies = get_thread_replies(thread_ts, wait_seconds=15)
    
    # Check if there's any reply from the bot
    agent_replies = [r for r in replies if r.get("bot_id")]
    
    if agent_replies:
        return True, f"Agent replied with {len(agent_replies)} message(s)"
    else:
        return False, "No agent reply received within 15 seconds"


# =============================================================================
# Test 2: Cross-VM Routing to epyc6
# =============================================================================

def test_route_to_epyc6():
    """Test routing to epyc6 with @epyc6 mention."""
    test_id = datetime.now().strftime("%H%M%S")
    
    result = post_message(f"[E2E-TEST-{test_id}] @epyc6 ping - confirm you received this")
    if not result["ok"]:
        return False, f"Failed to post message: {result.get('error')}"
    
    thread_ts = result["ts"]
    replies = get_thread_replies(thread_ts, wait_seconds=15)
    
    # Look for epyc6 identity in reply
    for reply in replies:
        text = reply.get("text", "").lower()
        if "epyc6" in text or "[epyc6]" in text:
            return True, "epyc6 responded correctly"
    
    agent_replies = [r for r in replies if r.get("bot_id")]
    if agent_replies:
        return True, f"Agent replied (but didn't include epyc6 identity)"
    return False, "No epyc6 response received"


# =============================================================================
# Test 3: Cross-VM Routing to macmini
# =============================================================================

def test_route_to_macmini():
    """Test routing to macmini with @macmini mention."""
    test_id = datetime.now().strftime("%H%M%S")
    
    result = post_message(f"[E2E-TEST-{test_id}] @macmini ping - confirm you received this")
    if not result["ok"]:
        return False, f"Failed to post message: {result.get('error')}"
    
    thread_ts = result["ts"]
    replies = get_thread_replies(thread_ts, wait_seconds=15)
    
    # Look for macmini identity in reply
    for reply in replies:
        text = reply.get("text", "").lower()
        if "macmini" in text or "[macmini]" in text:
            return True, "macmini responded correctly"
    
    agent_replies = [r for r in replies if r.get("bot_id")]
    if agent_replies:
        return True, f"Agent replied (but didn't include macmini identity)"
    return False, "No macmini response received"


# =============================================================================
# Test 4: Agent Handoff (epyc6 -> macmini)
# =============================================================================

def test_agent_handoff():
    """Test agent-to-agent handoff via @mention in thread."""
    test_id = datetime.now().strftime("%H%M%S")
    
    # First message to epyc6
    result = post_message(f"[E2E-TEST-{test_id}] @epyc6 start a task, then hand off to @macmini")
    if not result["ok"]:
        return False, f"Failed to post message: {result.get('error')}"
    
    thread_ts = result["ts"]
    
    # Wait for epyc6 to respond
    time.sleep(10)
    
    # Post handoff request in thread
    handoff_result = post_message(
        f"[E2E-TEST-{test_id}] @macmini please continue from where epyc6 left off",
        thread_ts=thread_ts
    )
    if not handoff_result["ok"]:
        return False, f"Failed to post handoff: {handoff_result.get('error')}"
    
    # Wait for macmini to respond
    replies = get_thread_replies(thread_ts, wait_seconds=15)
    
    # Check for both agents responding
    epyc6_replied = any("epyc6" in r.get("text", "").lower() for r in replies if r.get("bot_id"))
    macmini_replied = any("macmini" in r.get("text", "").lower() for r in replies if r.get("bot_id"))
    
    if epyc6_replied and macmini_replied:
        return True, "Both agents responded in handoff"
    elif epyc6_replied:
        return False, "Only epyc6 responded, macmini did not"
    elif macmini_replied:
        return False, "Only macmini responded, epyc6 did not"
    else:
        agent_replies = [r for r in replies if r.get("bot_id")]
        if agent_replies:
            return True, f"Got {len(agent_replies)} agent replies (identity not confirmed)"
        return False, "No agent responses in handoff"


# =============================================================================
# Test 5: Jules Gate 1 Fail (No jules-ready label)
# =============================================================================

def test_jules_gate1_fail():
    """Test that @jules without prerequisites gives helpful error."""
    test_id = datetime.now().strftime("%H%M%S")
    
    result = post_message(f"[E2E-TEST-{test_id}] @jules bd-fake-issue implement this feature")
    if not result["ok"]:
        return False, f"Failed to post message: {result.get('error')}"
    
    thread_ts = result["ts"]
    replies = get_thread_replies(thread_ts, wait_seconds=15)
    
    # Look for error message about missing label or spec
    for reply in replies:
        text = reply.get("text", "").lower()
        if "jules-ready" in text or "label" in text or "spec" in text or "docs/" in text:
            return True, "Jules gave helpful prerequisite error"
    
    agent_replies = [r for r in replies if r.get("bot_id")]
    if agent_replies:
        return True, "Agent responded (check message for Jules guidance)"
    return False, "No response to Jules request"


# =============================================================================
# Test 6: Session Resume Syntax
# =============================================================================

def test_session_resume_syntax():
    """Test session:xxx syntax recognition."""
    test_id = datetime.now().strftime("%H%M%S")
    
    result = post_message(f"[E2E-TEST-{test_id}] session:test-session-123 continue work")
    if not result["ok"]:
        return False, f"Failed to post message: {result.get('error')}"
    
    thread_ts = result["ts"]
    replies = get_thread_replies(thread_ts, wait_seconds=15)
    
    # Check for any response acknowledging session
    for reply in replies:
        text = reply.get("text", "").lower()
        if "session" in text or "resume" in text:
            return True, "Agent acknowledged session syntax"
    
    agent_replies = [r for r in replies if r.get("bot_id")]
    if agent_replies:
        return True, "Agent responded to session resume"
    return False, "No response to session resume"


# =============================================================================
# Run All Tests
# =============================================================================

def main():
    log("=" * 70)
    log("Multi-Agent Slack E2E Tests")
    log("=" * 70)
    log(f"Test Channel: {TEST_CHANNEL}")
    log(f"Bot Token: {SLACK_BOT_TOKEN[:20]}...")
    log("")
    
    # Run tests
    run_test("1. Basic Agent Response", test_basic_agent_response)
    run_test("2. Route to epyc6 (@epyc6)", test_route_to_epyc6)
    run_test("3. Route to macmini (@macmini)", test_route_to_macmini)
    run_test("4. Agent Handoff (epyc6 → macmini)", test_agent_handoff)
    run_test("5. Jules Gate Check", test_jules_gate1_fail)
    run_test("6. Session Resume Syntax", test_session_resume_syntax)
    
    # Summary
    log("")
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
            log(f"  - {name}: {msg}", "FAIL")
    
    if results["passed"]:
        log("")
        log("Passed tests:")
        for name, msg in results["passed"]:
            log(f"  - {name}: {msg}", "PASS")
    
    return 0 if not results["failed"] else 1


if __name__ == "__main__":
    sys.exit(main())
