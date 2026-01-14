#!/usr/bin/env python
"""
dx-dispatch - Dispatch tasks to remote OpenCode agents

Part of the agent-skills dx-* workflow.
Now uses lib/fleet for unified dispatch logic.

Usage:
    dx-dispatch <vm> <task> [options]
    dx-dispatch --list              # List available VMs
    dx-dispatch --status <vm>       # Check VM status

Examples:
    dx-dispatch epyc6 "Run make test in ~/affordabot"
    dx-dispatch macmini "Fix linting errors" --slack
    dx-dispatch epyc6 "Continue work" --session ses_abc123
    dx-dispatch --all "Run make verify-local"

Options:
    --session <id>    Resume existing session
    --slack           Post audit trail to Slack
    --no-slack        Skip Slack audit (default: audit enabled)
    --repo <name>     Target repository (e.g. prime-radiant-ai)
    --beads <id>      Beads ID for tracking (e.g. bd-123)
    --wait            Wait for completion
    --timeout <sec>   Timeout for --wait (default: 300)
    --smoke-pr        Create an empty PR for smoke testing (requires --repo + --beads)
"""

import os
import sys
import json
import argparse
from pathlib import Path
from datetime import datetime

# Add lib to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from lib.fleet import FleetDispatcher, DispatchResult
    from lib.fleet.backends.base import HealthStatus
    FLEET_AVAILABLE = True
except ImportError:
    FLEET_AVAILABLE = False
    print("Warning: lib/fleet not available, using legacy mode")

try:
    from slack_sdk import WebClient
except ImportError:
    WebClient = None


def log(msg: str, level: str = "INFO"):
    """Log with timestamp."""
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] [{level}] {msg}")


def post_to_slack(config: dict, message: str) -> bool:
    """Post message to Slack audit channel."""
    if WebClient is None:
        return False
    
    token_env = config.get("slack_bot_token_env", "SLACK_BOT_TOKEN")
    token = os.environ.get(token_env) or os.environ.get("SLACK_MCP_XOXP_TOKEN")
    
    if not token:
        log(f"Slack token not found in ${token_env}", "WARN")
        return False
    
    channel = config.get("slack_audit_channel")
    if not channel:
        log("No slack_audit_channel configured", "WARN")
        return False
    
    try:
        client = WebClient(token=token, timeout=5)
        client.chat_postMessage(channel=channel, text=message)
        return True
    except Exception as e:
        log(f"Slack post failed: {e}", "ERROR")
        return False


def load_legacy_config() -> dict:
    """Load VM endpoints configuration (legacy)."""
    config_path = Path.home() / ".agent-skills" / "vm-endpoints.json"
    if not config_path.exists():
        return {"vms": {}}
    
    with open(config_path) as f:
        return json.load(f)


def list_vms(dispatcher: FleetDispatcher):
    """List available VMs with status."""
    print("\n📡 Available VMs:\n")
    
    for backend in dispatcher._backends.values():
        if backend.backend_type == "opencode":
            health = backend.check_health()
            status = "🟢" if health == HealthStatus.HEALTHY else "🔴"
            print(f"  {status} {backend.name}")
            if health != HealthStatus.HEALTHY:
                print(f"      └── Status: {health.value}")
    
    # Show Jules
    jules = dispatcher._backends.get("jules-cloud")
    if jules:
        health = jules.check_health()
        status = "🟢" if health == HealthStatus.HEALTHY else "⚪"
        print(f"  {status} jules-cloud (cloud)")
    
    print()


def dispatch_with_fleet(args, config: dict, dispatcher: FleetDispatcher) -> str:
    """Dispatch using FleetDispatcher."""
    vm_name = args.vm
    task = args.task
    
    # Handle session resume
    if args.session:
        session_id = args.session
        # If vm argument looks like tasks (not a known VM), treat it as task part?
        # But simpler: check if we have a task. If task is None, maybe vm is task?
        if not task and vm_name and not dispatcher.get_backend(vm_name):
             task = vm_name
             vm_name = None # Derived from session
        
        # If still no task, default to "Continue"
        if not task:
            task = "Continue"

        log(f"Resuming session: {session_id}")
        log(f"Prompt: {task}")
        
        if dispatcher.continue_session(session_id, task):
             log("✅ Prompt sent to session")
             
             # Wait if requested
             if args.wait:
                 log(f"Waiting for completion (timeout: {args.timeout}s)...")
                 status = dispatcher.wait_for_completion(
                     session_id,
                     poll_interval_sec=10,
                     max_polls=args.timeout // 10
                 )
                 if status.get("status") == "completed":
                     log("✅ Task completed successfully")
                     if status.get("pr_url"):
                         print(f"PR: {status['pr_url']}")
                 else:
                     log(f"Task ended with status: {status.get('status')}", "WARN")
             
             return session_id
        else:
             log("Failed to resume session (not found or backend unavailable)", "ERROR")
             sys.exit(1)

    # Standard dispatch
    if not vm_name:
         log("Target VM required for new dispatch", "ERROR")
         sys.exit(1)

    # Audit to Slack (if enabled)
    hostname = os.uname().nodename
    if not args.no_slack:
        audit_msg = f"[{hostname}] 📤 Dispatching to {vm_name}:\n```\n{task[:200]}{'...' if len(task) > 200 else ''}\n```"
        if post_to_slack(config, audit_msg):
            log("Posted audit to Slack")
    
    # Determine mode
    mode = "smoke" if getattr(args, "smoke_pr", False) else "real"
    
    # Dispatch via FleetDispatcher
    log(f"Dispatching to {vm_name}...")
    result = dispatcher.dispatch(
        beads_id=args.beads or f"dispatch-{datetime.now().strftime('%H%M%S')}",
        prompt=task,
        repo=args.repo or "agent-skills",
        mode=mode,
        preferred_backend=vm_name,
    )
    
    if not result.success:
        log(f"Dispatch failed: {result.error}", "ERROR")
        if result.failure_code:
            log(f"Failure code: {result.failure_code}", "ERROR")
        if not args.no_slack:
            post_to_slack(config, f"[{vm_name}] ❌ Dispatch failed: {result.error}")
        sys.exit(1)
    
    if result.was_duplicate:
        log(f"Found existing session: {result.session_id}", "INFO")
    else:
        log(f"✅ Task dispatched successfully")
    
    log(f"Session ID: {result.session_id}")
    log(f"Backend: {result.backend_name} ({result.backend_type})")
    
    # Handle smoke PR
    if getattr(args, "smoke_pr", False):
        log("Creating smoke PR...")
        pr_url = dispatcher.finalize_pr(
            result.session_id, 
            args.beads, 
            smoke_mode=True
        )
        if pr_url:
            log(f"✅ Smoke PR created: {pr_url}")
            print(pr_url)
        else:
            log("Failed to create smoke PR", "ERROR")
            sys.exit(1)
        return result.session_id
    
    # Wait for completion if requested
    if args.wait:
        log(f"Waiting for completion (timeout: {args.timeout}s)...")
        status = dispatcher.wait_for_completion(
            result.session_id,
            poll_interval_sec=10,
            max_polls=args.timeout // 10
        )
        
        if status.get("status") == "completed":
            log("✅ Task completed successfully")
            if status.get("pr_url"):
                print(f"PR: {status['pr_url']}")
        else:
            log(f"Task ended with status: {status.get('status')}", "WARN")
            if status.get("failure_code"):
                log(f"Failure: {status.get('failure_code')}", "ERROR")
    
    # Audit completion
    if not args.no_slack:
        post_to_slack(config, f"[{vm_name}] ✅ Session {result.session_id} - task dispatched")
    
    # Print session info for follow-up
    print(f"\n📋 Session Info:")
    print(f"   VM: {result.backend_name}")
    print(f"   Session: {result.session_id}")
    print(f"   Status: dx-dispatch --status {result.backend_name}")
    print(f"   Resume: dx-dispatch {result.backend_name} \"continue\" --session {result.session_id}")
    
    return result.session_id


def check_status(args, dispatcher: FleetDispatcher):
    """Check status of a VM or session."""
    vm_name = args.status
    
    backend = dispatcher.get_backend(vm_name)
    if not backend:
        log(f"Unknown VM: {vm_name}", "ERROR")
        sys.exit(1)
    
    health = backend.check_health()
    if health == HealthStatus.HEALTHY:
        print(f"🟢 {vm_name} is healthy")
    else:
        print(f"🔴 {vm_name} is {health.value}")


def main():
    parser = argparse.ArgumentParser(
        description="Dispatch tasks to remote OpenCode agents",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument("vm", nargs="?", help="Target VM (e.g. epyc6, macmini)")
    parser.add_argument("task", nargs="?", help="Task description")
    parser.add_argument("--list", action="store_true", help="List available VMs")
    parser.add_argument("--status", metavar="VM", help="Check VM status")
    parser.add_argument("--session", help="Resume existing session")
    parser.add_argument("--slack", action="store_true", help="Post to Slack (default: enabled)")
    parser.add_argument("--no-slack", action="store_true", help="Skip Slack audit")
    parser.add_argument("--repo", help="Target repository")
    parser.add_argument("--beads", help="Beads ID for tracking")
    parser.add_argument("--wait", action="store_true", help="Wait for completion")
    parser.add_argument("--timeout", type=int, default=300, help="Timeout in seconds")
    parser.add_argument("--smoke-pr", action="store_true", help="Create smoke PR")
    parser.add_argument("--all", action="store_true", help="Dispatch to all VMs")
    parser.add_argument("--shell", action="store_true", help="Use shell mode (legacy)")
    parser.add_argument("--attach", action="store_true", help="Use attach mode (legacy)")
    
    args = parser.parse_args()
    
    # Load config
    config = load_legacy_config()
    
    # Initialize FleetDispatcher
    if not FLEET_AVAILABLE:
        log("lib/fleet not available. Please ensure it's installed.", "ERROR")
        sys.exit(1)
    
    dispatcher = FleetDispatcher()
    
    # Handle commands
    if args.list:
        list_vms(dispatcher)
        return
    
    if args.status:
        check_status(args, dispatcher)
        return
    
    # Validate args
    if not args.session and (not args.vm or not args.task):
        parser.print_help()
        sys.exit(1)
    
    # Dispatch
    dispatch_with_fleet(args, config, dispatcher)


if __name__ == "__main__":
    main()
