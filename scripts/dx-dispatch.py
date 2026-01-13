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
    --repo <name>     Target repository (e.g. prime-radiant-ai)
    --beads <id>      Beads ID for tracking (e.g. bd-123)
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


def setup_worktree(ssh: str, beads_id: str, repo: str) -> str:
    """Create isolated worktree for agent."""
    # Source .zshenv to get LLM API keys, then run worktree setup
    cmd = f"source ~/.zshenv 2>/dev/null; ~/bin/worktree-setup.sh {beads_id} {repo}"
    
    # Try SSH run
    if ssh:
        try:
            result = subprocess.run(
                ["ssh", ssh, cmd],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode == 0:
                worktree_path = result.stdout.strip()
                # Validate output looks like a path
                if worktree_path.startswith("/"):
                     return worktree_path
            
            # If failed, log stderr
            log(f"Worktree setup failed: {result.stderr}", "ERROR")
            
        except Exception as e:
            log(f"Worktree setup error: {e}", "ERROR")
    
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


def send_to_session_shell(opencode_url: str, session_id: str, command: str, timeout: int = 300, ssh: str = None) -> dict:
    """Send direct shell command to OpenCode session (bypassing agent tool loop)."""
    # Try direct HTTP first
    try:
        resp = httpx.post(
            f"{opencode_url}/session/{session_id}/shell",
            json={"agent": "build", "command": command},
            timeout=timeout
        )
        return resp.json()
    except Exception:
        pass  # Fall through to SSH
    
    if ssh:
        try:
            # Payload for curl to read from stdin
            payload = json.dumps({"agent": "build", "command": command})
            
            # When running via SSH on the target, use localhost relative to that target
            # (The external URL might be tailscale/DNS which is not resolvable or bound locally)
            from urllib.parse import urlparse
            parsed = urlparse(opencode_url)
            port = parsed.port or 4105
            local_url = f"http://localhost:{port}"

            cmd = [
                "ssh", ssh,
                f"curl -v -X POST {local_url}/session/{session_id}/shell -H 'Content-Type: application/json' -d @-"
            ]
            
            # Pass payload via stdin to avoid shell quoting hell
            result = subprocess.run(cmd, input=payload, capture_output=True, text=True, timeout=timeout)
            
            if result.returncode == 0:
                return json.loads(result.stdout) if result.stdout.strip() else {"ok": True}
            else:
                log(f"SSH stderr: {result.stderr}", "ERROR")
        except subprocess.TimeoutExpired:
            return {"ok": True, "note": "Shell command dispatched (SSH timeout, still running)"}
        except Exception as e:
            log(f"SSH shell send failed: {e}", "ERROR")

    return {"error": "Failed to send shell command"}



def get_resource_config(beads_id: str) -> dict:
    """Generate isolated resource config from beads ID."""
    # Deterministic port based on hash
    # Use simple sum of chars or similar for stability
    # (hash() in python is randomized per process unless configured)
    import hashlib
    h = hashlib.md5(beads_id.encode()).hexdigest()
    port_offset = int(h, 16) % 2000  # 0-1999
    port = 3000 + port_offset
    
    # Schema name (sanitize for SQL)
    schema = beads_id.replace("-", "_").lower()
    
    return {"port": port, "schema": schema}

def send_task_with_context(opencode_url: str, session_id: str, user_input: str, worktree: str, beads_id: str, timeout: int = 300, ssh: str = None, shell_mode: bool = False) -> dict:
    """Send task with directory context and resource isolation instructions."""
    resources = get_resource_config(beads_id)
    port = resources["port"]
    schema = resources["schema"]

    if shell_mode:
        # Construct compound shell command for direct execution
        # We export env vars for the duration of the subshell/command chain
        command = (
            f"export PORT={port} && "
            f"export DB_SCHEMA='{schema}' && "
            f"cd {worktree} && "
            f"{user_input}"
        )
        return send_to_session_shell(opencode_url, session_id, command, timeout=timeout, ssh=ssh)

    # API doesn't support directory, so we wrap the prompt
    context_prompt = (
        f"IMPORTANT: You are working in an isolated worktree at: {worktree}\n"
        f"You MUST use `cd {worktree} && pwd` as your first command (to verify location and ensure output).\n"
        f"All your work (edits, commits) must happen in this directory.\n"
        f"DO NOT work in the default repo location.\n\n"
        f"RESOURCE ISOLATION REQUIRED:\n"
        f"- You MUST run your dev server on PORT={port}\n"
        f"- You MUST use Database Schema: '{schema}' (create if needed)\n"
        f"- Do NOT use default ports (3000, 8000) or public schemas.\n"
        f"- IMPORTANT: Env vars do NOT persist between tool calls. Set them in every command or use a .env file.\n\n"
        f"Task:\n{user_input}"
    )
    return send_to_session(opencode_url, session_id, context_prompt, timeout=timeout, ssh=ssh)


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

    # Setup Worktree if beads ID provided
    worktree_path = None
    if args.beads and args.repo:
        log(f"Setting up isolated worktree for {args.beads}...", "INFO")
        worktree_path = setup_worktree(ssh, args.beads, args.repo)
        
        if worktree_path:
            log(f"Worktree created at: {worktree_path}", "INFO")
        else:
            log("Failed to setup worktree. Aborting to prevent conflicts.", "ERROR")
            sys.exit(1)
    
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
    
    # Send task
    log(f"Sending task to {vm_name}...")
    
    if worktree_path:
        # Pass beads_id for resource calculation
        result = send_task_with_context(opencode_url, session_id, task, worktree_path, args.beads, args.timeout, ssh=ssh, shell_mode=args.shell)
    else:
        # Legacy/Simple mode
        prompt = task
        if args.repo:
            prompt = f"Repo: {args.repo}\n\n{task}"
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
    
    print("\n📊 Dispatch Summary:")
    for vm, res in results.items():
        status = "✅" if res["success"] else "❌"
        sess = res.get("session", "")
        print(f"{status} {vm}: {sess}")


def main():
    parser = argparse.ArgumentParser(description="Dispatch tasks to OpenCode agents")
    
    # Direct dispatch (default)
    parser.add_argument("vm", nargs="?", help="Target VM name (e.g. epyc6)")
    parser.add_argument("task", nargs="?", help="Task description")
    parser.add_argument("--session", help="Resume existing session")
    parser.add_argument("--slack", action="store_true", help="Audit via Slack (deprecated, on by default)")
    parser.add_argument("--no-slack", action="store_true", help="Disable Slack audit")
    parser.add_argument("--all", action="store_true", help="Dispatch to all VMs")
    parser.add_argument("--repo", help="Target repository (e.g. prime-radiant-ai)")
    parser.add_argument("--beads", help="Beads ID for tracking (e.g. bd-123)")
    parser.add_argument("--wait", action="store_true", help="Wait for completion")
    parser.add_argument("--timeout", type=int, default=300, help="Timeout in seconds")
    parser.add_argument("--shell", action="store_true", help="Run task as direct shell command (bypassing agent reasoning)")
    
    # Commands
    parser.add_argument("--list", action="store_true", help="List available VMs")
    parser.add_argument("--status", help="Check status of specific VM")
    
    args = parser.parse_args()
    config = load_config()
    
    if args.list:
        list_vms(config)
        return
        
    if args.status:
        args.vm = args.status
        # Just check health
        vm_name = args.vm
        if vm_name not in config.get("vms", {}):
            log(f"Unknown VM: {vm_name}", "ERROR")
            sys.exit(1)
            
        vm = config["vms"][vm_name]
        health = check_vm_health(vm.get("opencode"), ssh=vm.get("ssh"))
        status = "✅ Online" if health.get("healthy") else "❌ Offline"
        print(f"{vm_name}: {status} (v{health.get('version', 'N/A')})")
        if not health.get("healthy"):
            print(f"Error: {health.get('error')}")
        return

    if args.all:
        if not args.task:
            print("Error: Task is required for --all")
            sys.exit(1)
        dispatch_all(args, config)
        return

    if not args.vm or not args.task:
        parser.print_help()
        sys.exit(1)
        
    dispatch(args, config)


if __name__ == "__main__":
    main()
