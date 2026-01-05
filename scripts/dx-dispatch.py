#!/usr/bin/env python3
"""
dx-dispatch - Dispatch tasks to remote OpenCode agents

Part of the agent-skills dx-* workflow.

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
    --repo <name>     Specify repo context
    --wait            Wait for completion
    --timeout <sec>   Timeout for --wait (default: 300)
"""

import os
import sys
import json
import argparse
import subprocess
from pathlib import Path
from datetime import datetime

try:
    import httpx
except ImportError:
    print("Installing httpx...")
    subprocess.run([sys.executable, "-m", "pip", "install", "httpx", "-q"])
    import httpx

try:
    from slack_sdk import WebClient
except ImportError:
    print("Installing slack-sdk...")
    subprocess.run([sys.executable, "-m", "pip", "install", "slack-sdk", "-q"])
    from slack_sdk import WebClient

# Configuration
CONFIG_PATH = Path.home() / ".agent-skills" / "vm-endpoints.json"


def load_config():
    """Load VM endpoints configuration."""
    if not CONFIG_PATH.exists():
        print(f"❌ Config not found: {CONFIG_PATH}")
        print("Run: dx-hydrate to create config")
        sys.exit(1)
    
    with open(CONFIG_PATH) as f:
        return json.load(f)


def log(msg: str, level: str = "INFO"):
    """Log with timestamp."""
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] [{level}] {msg}")


def post_to_slack(config: dict, message: str) -> bool:
    """Post message to Slack audit channel."""
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
        client = WebClient(token=token)
        client.chat_postMessage(channel=channel, text=message)
        return True
    except Exception as e:
        log(f"Slack post failed: {e}", "ERROR")
        return False


def check_vm_health(opencode_url: str, ssh: str = None) -> dict:
    """Check OpenCode server health."""
    # Try direct HTTP first
    try:
        resp = httpx.get(f"{opencode_url}/global/health", timeout=5)
        if resp.status_code == 200:
            return resp.json()
    except Exception:
        pass  # Fall through to SSH
    
    # Try SSH if available
    if ssh:
        try:
            result = subprocess.run(
                ["ssh", ssh, "curl -s http://localhost:4105/global/health"],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                return json.loads(result.stdout)
        except Exception as e:
            return {"healthy": False, "error": f"SSH failed: {e}"}
    
    return {"healthy": False, "error": "Unreachable"}


def create_session(opencode_url: str, title: str, ssh: str = None) -> str:
    """Create a new OpenCode session."""
    # Try direct HTTP first
    try:
        resp = httpx.post(
            f"{opencode_url}/session",
            json={"title": title},
            timeout=10
        )
        data = resp.json()
        return data.get("id")
    except Exception:
        pass  # Fall through to SSH
    
    # Try SSH if available
    if ssh:
        try:
            result = subprocess.run(
                ["ssh", ssh, f'curl -s -X POST http://localhost:4105/session -H "Content-Type: application/json" -d \'{{"title":"{title}"}}\''],
                capture_output=True, text=True, timeout=15
            )
            if result.returncode == 0:
                data = json.loads(result.stdout)
                return data.get("id")
        except Exception as e:
            log(f"SSH session creation failed: {e}", "ERROR")
    
    return None


def send_to_session(opencode_url: str, session_id: str, prompt: str, timeout: int = 300, ssh: str = None) -> dict:
    """Send prompt to OpenCode session."""
    # Try direct HTTP first
    try:
        resp = httpx.post(
            f"{opencode_url}/session/{session_id}/message",
            json={"parts": [{"type": "text", "text": prompt}]},
            timeout=timeout
        )
        return resp.json()
    except Exception:
        pass  # Fall through to SSH
    
    # Try SSH if available - use async approach
    if ssh:
        try:
            # Escape the prompt for shell
            escaped_prompt = prompt.replace('"', '\\"').replace("'", "'\\''")
            payload = json.dumps({"parts": [{"type": "text", "text": prompt}]})
            payload_escaped = payload.replace('"', '\\"')
            
            result = subprocess.run(
                ["ssh", ssh, f'curl -s -X POST http://localhost:4105/session/{session_id}/message -H "Content-Type: application/json" -d \'{payload}\''],
                capture_output=True, text=True, timeout=timeout
            )
            if result.returncode == 0:
                return json.loads(result.stdout) if result.stdout.strip() else {"ok": True}
        except subprocess.TimeoutExpired:
            return {"ok": True, "note": "Task dispatched (SSH timeout, still running)"}
        except Exception as e:
            log(f"SSH send failed: {e}", "ERROR")
    
    return {"error": "Failed to send"}


def list_vms(config: dict):
    """List available VMs with status."""
    print("\n📍 Available VMs:\n")
    print(f"{'VM':<15} {'Status':<12} {'URL':<45} {'Description'}")
    print("-" * 90)
    
    for name, vm in config.get("vms", {}).items():
        url = vm.get("opencode", "N/A")
        ssh = vm.get("ssh")
        desc = vm.get("description", "")
        
        health = check_vm_health(url, ssh=ssh)
        if health.get("healthy"):
            status = "✅ Online"
            version = health.get("version", "")
        else:
            status = "❌ Offline"
            version = ""
        
        default = " (default)" if name == config.get("default_vm") else ""
        print(f"{name:<15} {status:<12} {url:<45} {desc}{default}")
    
    print()


def dispatch(args, config: dict):
    """Dispatch task to VM."""
    vm_name = args.vm
    task = args.task
    
    # Get VM config
    vms = config.get("vms", {})
    if vm_name not in vms:
        log(f"Unknown VM: {vm_name}. Available: {', '.join(vms.keys())}", "ERROR")
        sys.exit(1)
    
    vm = vms[vm_name]
    opencode_url = vm.get("opencode")
    ssh = vm.get("ssh")
    
    # Check health
    log(f"Checking {vm_name} health...")
    health = check_vm_health(opencode_url, ssh=ssh)
    if not health.get("healthy"):
        log(f"{vm_name} is not healthy: {health.get('error')}", "ERROR")
        sys.exit(1)
    
    log(f"✅ {vm_name} is healthy (v{health.get('version', 'unknown')})")
    
    # Audit to Slack (if enabled)
    hostname = os.uname().nodename
    if not args.no_slack:
        audit_msg = f"[{hostname}] 📤 Dispatching to {vm_name}:\n```\n{task[:200]}{'...' if len(task) > 200 else ''}\n```"
        if post_to_slack(config, audit_msg):
            log("Posted audit to Slack")
    
    # Create or resume session
    if args.session:
        session_id = args.session
        log(f"Resuming session: {session_id}")
    else:
        title = f"{args.repo or 'task'}-{datetime.now().strftime('%H%M%S')}"
        session_id = create_session(opencode_url, title, ssh=ssh)
        if not session_id:
            log("Failed to create session", "ERROR")
            sys.exit(1)
        log(f"Created session: {session_id}")
    
    # Build prompt with context
    prompt = task
    if args.repo:
        prompt = f"Repo: {args.repo}\n\n{task}"
    
    # Send task
    log(f"Sending task to {vm_name}...")
    result = send_to_session(opencode_url, session_id, prompt, args.timeout, ssh=ssh)
    
    if "error" in result:
        log(f"Task failed: {result['error']}", "ERROR")
        # Audit failure
        if not args.no_slack:
            post_to_slack(config, f"[{vm_name}] ❌ Task failed: {result['error']}")
        sys.exit(1)
    
    # Success
    log(f"✅ Task dispatched successfully")
    log(f"Session ID: {session_id}")
    
    # Audit completion
    if not args.no_slack:
        post_to_slack(config, f"[{vm_name}] ✅ Session {session_id} - task dispatched")
    
    # Print session info for follow-up
    print(f"\n📋 Session Info:")
    print(f"   VM: {vm_name}")
    print(f"   Session: {session_id}")
    print(f"   Resume: dx-dispatch {vm_name} \"continue\" --session {session_id}")
    
    return session_id


def dispatch_all(args, config: dict):
    """Dispatch task to all VMs."""
    vms = config.get("vms", {})
    results = {}
    
    for vm_name in vms:
        log(f"Dispatching to {vm_name}...")
        args.vm = vm_name
        try:
            session_id = dispatch(args, config)
            results[vm_name] = {"success": True, "session": session_id}
        except SystemExit:
            results[vm_name] = {"success": False}
    
    # Summary
    print("\n📊 Dispatch Summary:")
    for vm_name, result in results.items():
        status = "✅" if result.get("success") else "❌"
        session = result.get("session", "N/A")
        print(f"   {status} {vm_name}: {session}")


def main():
    parser = argparse.ArgumentParser(
        description="Dispatch tasks to remote OpenCode agents",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument("vm", nargs="?", help="Target VM (or --list)")
    parser.add_argument("task", nargs="?", help="Task to dispatch")
    parser.add_argument("--list", action="store_true", help="List available VMs")
    parser.add_argument("--status", metavar="VM", help="Check VM status")
    parser.add_argument("--session", help="Resume existing session")
    parser.add_argument("--slack", action="store_true", default=True, help="Post to Slack (default)")
    parser.add_argument("--no-slack", action="store_true", help="Skip Slack audit")
    parser.add_argument("--repo", help="Repo context")
    parser.add_argument("--all", action="store_true", help="Dispatch to all VMs")
    parser.add_argument("--timeout", type=int, default=300, help="Request timeout")
    
    args = parser.parse_args()
    
    # Load config
    config = load_config()
    
    # Handle commands
    if args.list:
        list_vms(config)
        return
    
    if args.status:
        vm = config.get("vms", {}).get(args.status)
        if not vm:
            print(f"Unknown VM: {args.status}")
            sys.exit(1)
        health = check_vm_health(vm["opencode"])
        print(json.dumps(health, indent=2))
        return
    
    if args.all and args.task:
        args.vm = None  # Will be set per-VM
        dispatch_all(args, config)
        return
    
    if not args.vm or not args.task:
        parser.print_help()
        print("\n💡 Examples:")
        print('   dx-dispatch epyc6 "Run make test"')
        print('   dx-dispatch macmini "Fix linting" --repo affordabot')
        print("   dx-dispatch --list")
        sys.exit(1)
    
    dispatch(args, config)


if __name__ == "__main__":
    main()
