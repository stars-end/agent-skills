#!/usr/bin/env python
from __future__ import annotations

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
import shlex
import shutil
import subprocess
from pathlib import Path
from datetime import datetime
from typing import TYPE_CHECKING, Optional, Any

# Add lib to path for imports (use resolve() to follow symlinks)
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Type-only imports (not evaluated at runtime due to __future__ annotations)
if TYPE_CHECKING:
    from lib.fleet import FleetDispatcher, DispatchResult
    from lib.fleet.backends.base import HealthStatus

# Runtime imports with fallback
try:
    from lib.fleet import FleetDispatcher, DispatchResult
    from lib.fleet.backends.base import HealthStatus

    FLEET_AVAILABLE = True
except ImportError:
    FLEET_AVAILABLE = False
    FleetDispatcher = None  # type: ignore[misc,assignment]
    DispatchResult = None  # type: ignore[misc,assignment]
    HealthStatus = None  # type: ignore[misc,assignment]
    print("Warning: lib/fleet not available, using legacy mode", file=sys.stderr)

try:
    from slack_sdk import WebClient
except ImportError:
    WebClient = None


def log(msg: str, level: str = "INFO"):
    """Log with timestamp."""
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] [{level}] {msg}")


def run_auto_checkpoint(repo_path: Path) -> None:
    """Best-effort: run auto-checkpoint for a repo path to avoid losing work.

    This is intentionally non-blocking for dispatch: failures only emit warnings.
    """
    try:
        if shutil.which("auto-checkpoint") is None:
            return
        if not repo_path.exists():
            return
        log(f"auto-checkpoint: {repo_path}")
        result = subprocess.run(
            ["auto-checkpoint", str(repo_path)],
            capture_output=True,
            text=True,
            timeout=300,
        )
        if result.returncode not in (0, 1):
            log(f"auto-checkpoint exited {result.returncode} (continuing)", "WARN")
    except subprocess.TimeoutExpired:
        log("auto-checkpoint timed out (continuing)", "WARN")
    except Exception as e:
        log(f"auto-checkpoint error: {e}", "WARN")


def run_sync_before_dispatch(repo: str = None) -> bool:
    """Run ru sync before dispatching to ensure repos are fresh.

    Args:
        repo: Specific repo to sync (e.g., 'agent-skills', 'prime-radiant-ai')

    Returns:
        True if sync succeeded or was skipped (dirty tree), False on error
    """
    import subprocess

    try:
        # Build ru command
        cmd = ["ru", "sync", "--non-interactive", "--quiet"]
        if repo:
            cmd.append(repo)

        log(f"Syncing {repo or 'all repos'} before dispatch...")
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,  # 2 minute timeout
        )

        # Exit 0 = success, 1 = partial (some repos failed), 5 = interrupted
        # We accept all of these - dirty trees are expected and skipped
        if result.returncode in (0, 1, 5):
            if result.returncode == 1:
                log("Some repos skipped (likely dirty tree or network)", "WARN")
            return True
        else:
            log(f"ru sync failed with exit code {result.returncode}", "WARN")
            if result.stderr:
                log(f"ru stderr: {result.stderr}", "DEBUG")
            return False

    except subprocess.TimeoutExpired:
        log("ru sync timed out (120s)", "WARN")
        return False
    except FileNotFoundError:
        log("ru not found in PATH (sync skipped)", "WARN")
        return True  # Not an error - just skip
    except Exception as e:
        log(f"ru sync error: {e}", "WARN")
        return True  # Don't block dispatch on sync failures


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

    # Durability first: best-effort checkpoint to avoid losing work and to keep
    # canonical clones fast-forwardable for ru sync.
    run_auto_checkpoint(Path.home() / "agent-skills")
    if hasattr(args, "repo") and args.repo:
        run_auto_checkpoint(Path.home() / args.repo)

    # Sync before dispatch to ensure repos are fresh
    # Sync agent-skills first (highest churn)
    run_sync_before_dispatch("agent-skills")

    # If --repo specified, sync that too
    if hasattr(args, "repo") and args.repo:
        run_sync_before_dispatch(args.repo)

    # Handle session resume
    if args.session:
        session_id = args.session
        # If vm argument looks like tasks (not a known VM), treat it as task part?
        # But simpler: check if we have a task. If task is None, maybe vm is task?
        if not task and vm_name and not dispatcher.get_backend(vm_name):
            task = vm_name
            vm_name = None  # Derived from session

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
                    session_id, poll_interval_sec=10, max_polls=args.timeout // 10
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

    # For smoke PR, suppress prompt to avoid race with finalize_pr
    prompt_to_send = task
    if getattr(args, "smoke_pr", False):
        prompt_to_send = ""

    result = dispatcher.dispatch(
        beads_id=args.beads or f"dispatch-{datetime.now().strftime('%H%M%S')}",
        prompt=prompt_to_send,
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
        pr_url = dispatcher.finalize_pr(result.session_id, args.beads, smoke_mode=True)
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
            result.session_id, poll_interval_sec=10, max_polls=args.timeout // 10
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
        post_to_slack(
            config, f"[{vm_name}] ✅ Session {result.session_id} - task dispatched"
        )

    # Print session info for follow-up
    print(f"\n📋 Session Info:")
    print(f"   VM: {result.backend_name}")
    print(f"   Session: {result.session_id}")
    print(f"   Status: dx-dispatch --status {result.backend_name}")
    print(
        f'   Resume: dx-dispatch {result.backend_name} "continue" --session {result.session_id}'
    )

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


def get_beads_issue(issue_id: str) -> dict:
    """Fetch issue details from Beads as JSON."""
    try:
        result = subprocess.run(
            ["bd", "show", issue_id, "--json"],
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        log(f"Error fetching issue {issue_id}: {e.stderr}", "ERROR")
        sys.exit(1)
    except json.JSONDecodeError:
        log(f"Error parsing JSON for issue {issue_id}", "ERROR")
        sys.exit(1)


def identify_context_skills(issue: dict) -> list[str]:
    """Match context skills based on keywords.

    Simplified version of matching logic.
    """
    text = (issue.get("title", "") + " " + issue.get("description", "")).lower()
    skills = []

    mapping = {
        "context-database-schema": [
            "database",
            "schema",
            "migration",
            "sql",
            "table",
            "supabase",
        ],
        "context-api-contracts": ["api", "endpoint", "rest", "route", "controller"],
        "context-ui-design": [
            "ui",
            "frontend",
            "css",
            "component",
            "react",
            "tailwind",
        ],
        "context-infrastructure": [
            "ci",
            "railway",
            "deploy",
            "docker",
            "github actions",
        ],
        "context-analytics": ["analytics", "tracking", "metrics"],
        "context-security-resolver": [
            "security",
            "resolver",
            "cusip",
            "isin",
            "symbol",
        ],
    }

    for skill, keywords in mapping.items():
        if any(k in text for k in keywords):
            skills.append(skill)

    return skills if skills else ["area-context-create"]  # Fallback


def generate_jules_prompt(issue: dict, skills: list[str]) -> str:
    """Construct the rich prompt for Jules."""
    issue_id = issue.get("id")
    title = issue.get("title")
    desc = issue.get("description")

    skills_str = "\\n".join([f"- {s}" for s in skills])

    return f"""
TASK: {title} ({issue_id})

CONTEXT:
- Repository: Current
- Branch: feature-{issue_id}-jules

🚨 INSTRUCTIONS:

1. INVOKE SKILLS:
   Identify and invoke relevant context skills to understand the codebase.
   Recommended based on keywords:
{skills_str}

2. EXPLORE:
   - Use `find_by_name` or `grep_search` to find relevant files.
   - Read the SKILL.md of invoked context skills for map of the area.
   - Don't guess. Verify existing code first.

3. PLAN & EXECUTE:
   - Checkout branch: `git checkout -b feature-{issue_id}-jules`
   - Implement changes.
   - Verify with tests if possible.
   - Commit with `Feature-Key: {issue_id}` trailer.
   - Push and create PR using `gh pr create`.

ISSUE DETAILS:
{desc}
"""


def dispatch_jules(issue_id: str, dry_run: bool = False) -> int:
    """Dispatch a Beads issue to Jules Cloud.

    Args:
        issue_id: Beads issue ID (e.g. bd-123)
        dry_run: Print command without executing

    Returns:
        Exit code (0 for success, 1 for failure)
    """
    log(f"Processing {issue_id}...")
    issue = get_beads_issue(issue_id)
    skills = identify_context_skills(issue)
    prompt = generate_jules_prompt(issue, skills)

    cmd = ["jules", "remote", "new", "--repo", ".", "--session", prompt]

    if dry_run:
        log(f"--- Dry Run {issue_id} ---")
        print(" ".join(shlex.quote(arg) for arg in cmd))
        log("--- End Prompt ---")
        print(prompt[:500] + "..." if len(prompt) > 500 else prompt)
        return 0

    log(f"🚀 Dispatching {issue_id} to Jules...")
    try:
        subprocess.run(cmd, check=True)
        log(f"✅ Dispatched {issue_id}")
        return 0
    except subprocess.CalledProcessError:
        log(f"❌ Failed to dispatch {issue_id}", "ERROR")
        return 1
    except FileNotFoundError:
        log("jules CLI not found in PATH", "ERROR")
        return 1


def cmd_finalize_pr(args, dispatcher: FleetDispatcher) -> int:
    """Finalize PR for an OpenCode session."""
    pr_url = dispatcher.finalize_pr(
        session_id=args.finalize_pr,
        beads_id=args.beads,
        smoke_mode=getattr(args, "smoke", False),
    )
    if pr_url:
        log(f"✅ PR finalized: {pr_url}")
        print(pr_url)
        return 0
    else:
        log("Failed to finalize PR", "ERROR")
        status = dispatcher.get_status(args.finalize_pr)
        log(f"Session status: {status}", "DEBUG")
        return 2


def cmd_abort(args, dispatcher: FleetDispatcher) -> int:
    """Abort a running session (best-effort)."""
    record = dispatcher.state_store.find_by_session_id(args.abort)
    if not record:
        log("Session not found in fleet-state.json", "ERROR")
        return 2

    backend = dispatcher.get_backend(record.backend_name)
    if not backend:
        log(f"Backend not found: {record.backend_name}", "ERROR")
        return 2

    ok = backend.abort_session(args.abort)
    if ok:
        log(f"✅ Session {args.abort} aborted")
        return 0
    else:
        log(f"Failed to abort session {args.abort}", "ERROR")
        return 2


def main():
    parser = argparse.ArgumentParser(
        description="Dispatch tasks to remote OpenCode agents",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    parser.add_argument("vm", nargs="?", help="Target VM (e.g. epyc6, macmini)")
    parser.add_argument("task", nargs="?", help="Task description")
    parser.add_argument("--list", action="store_true", help="List available VMs")
    parser.add_argument("--status", metavar="VM", help="Check VM status")
    parser.add_argument("--session", help="Resume existing session")
    parser.add_argument(
        "--slack", action="store_true", help="Post to Slack (default: enabled)"
    )
    parser.add_argument("--no-slack", action="store_true", help="Skip Slack audit")
    parser.add_argument("--repo", help="Target repository")
    parser.add_argument("--beads", help="Beads ID for tracking")
    parser.add_argument("--wait", action="store_true", help="Wait for completion")
    parser.add_argument("--timeout", type=int, default=300, help="Timeout in seconds")
    parser.add_argument("--smoke-pr", action="store_true", help="Create smoke PR")
    parser.add_argument("--all", action="store_true", help="Dispatch to all VMs")
    parser.add_argument("--shell", action="store_true", help="Use shell mode (legacy)")
    parser.add_argument(
        "--attach", action="store_true", help="Use attach mode (legacy)"
    )
    parser.add_argument(
        "--jules",
        action="store_true",
        help="Dispatch to Jules Cloud (requires --issue)",
    )
    parser.add_argument(
        "--issue", "-i", help="Beads issue ID to dispatch (required for --jules)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print command without executing (Jules mode)",
    )
    parser.add_argument(
        "--finalize-pr",
        metavar="SESSION",
        help="Finalize PR for an OpenCode session (requires --beads)",
    )
    parser.add_argument("--abort", metavar="SESSION", help="Abort a running session")

    args = parser.parse_args()

    # Handle --jules mode (dispatches Beads issues to Jules Cloud)
    if args.jules:
        if not args.issue:
            log("Error: --issue required with --jules", "ERROR")
            sys.exit(1)
        sys.exit(dispatch_jules(args.issue, args.dry_run))

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

    # Handle --finalize-pr command
    if args.finalize_pr:
        if not args.beads:
            log("Error: --beads required with --finalize-pr", "ERROR")
            sys.exit(1)
        sys.exit(cmd_finalize_pr(args, dispatcher))

    # Handle --abort command
    if args.abort:
        sys.exit(cmd_abort(args, dispatcher))

    # Validate args
    if not args.session and (not args.vm or not args.task):
        parser.print_help()
        sys.exit(1)

    # Dispatch
    dispatch_with_fleet(args, config, dispatcher)


if __name__ == "__main__":
    main()
