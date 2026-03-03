#!/usr/bin/env python3
"""
jules-dispatch/dispatch.py - Cross-repo Jules dispatcher

Scans for 'jules-ready' Beads tasks and dispatches them to Jules.
Works from any Beads-enabled repository.

Usage:
    python ~/.agent/skills/jules-dispatch/dispatch.py [options]

Options:
    --dry-run       Print commands without executing
    --issue ID      Dispatch specific issue only
    --force         Ignore 'jules-ready' label check
    --repo OWNER/NAME  Override auto-detected repo
"""

import json
import subprocess
import sys
import argparse
import re
import os
import shutil
import time
from pathlib import Path
from typing import List, Dict, Optional

# Constants
BEADS_FILE = ".beads/issues.jsonl"
CANONICAL_BEADS_REPO = Path.home() / "bd"
DOCS_DIR = "docs"
LABEL_TRIGGER = "jules-ready"

QUOTA_ERROR_PATTERNS: List[re.Pattern[str]] = [
    re.compile(r"\bRESOURCE_EXHAUSTED\b", re.IGNORECASE),
    re.compile(r"\ball sessions failed to create\b", re.IGNORECASE),
    re.compile(r"\bquota\b", re.IGNORECASE),
]


def _looks_like_quota_error(output: str) -> bool:
    return any(p.search(output) for p in QUOTA_ERROR_PATTERNS)


def find_repo_root() -> Optional[Path]:
    """Find the git repository root from current directory."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True
        )
        return Path(result.stdout.strip())
    except subprocess.CalledProcessError:
        return None


def get_repo_name() -> Optional[str]:
    """Get the GitHub owner/repo from git remote."""
    try:
        result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            capture_output=True,
            text=True,
            check=True
        )
        url = result.stdout.strip()
        
        # Handle SSH format: git@github.com:owner/repo.git
        if url.startswith("git@"):
            parts = url.split(":")[-1]
            return parts.replace(".git", "")
        
        # Handle HTTPS format: https://github.com/owner/repo.git
        if "github.com" in url:
            parts = url.split("github.com/")[-1]
            return parts.replace(".git", "")
        
        return None
    except subprocess.CalledProcessError:
        return None


def load_issues(repo_root: Path) -> List[Dict]:
    """Load issues from canonical Beads (`~/bd`) by default.

    Falls back to local `.beads/issues.jsonl` only when explicitly
    enabled for legacy compatibility.
    """
    issues = load_issues_from_bd_cli()
    if issues:
        return issues

    if os.getenv("ALLOW_LEGACY_BEADS_JSONL", "0") != "1":
        print("⚠️  Beads CLI unavailable; legacy JSONL source is disabled for this run")
        print("    Set ALLOW_LEGACY_BEADS_JSONL=1 to enable compatibility fallback.")
        return []

    beads_path = repo_root / BEADS_FILE
    if not beads_path.exists():
        print(f"⚠️  Beads CLI unavailable and no local issues file at {beads_path}")
        return []
    print(f"⚠️  Falling back to legacy JSONL source: {beads_path}")
    return load_issues_from_jsonl(beads_path)


def load_issues_from_bd_cli() -> List[Dict]:
    """Load open issues using the canonical Beads CLI (hub-spoke path)."""
    if not shutil.which("bd"):
        return []

    try:
        result = subprocess.run(
            ["bd", "list", "--json", "--status", "open", "--limit", "0"],
            cwd=str(CANONICAL_BEADS_REPO),
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []

    raw = result.stdout.strip()
    if not raw:
        return []

    try:
        payload = json.loads(raw)
        if isinstance(payload, list):
            return payload
    except json.JSONDecodeError:
        return []

    return []


def load_issues_from_jsonl(path: Path) -> List[Dict]:
    """Load all issues from legacy `.beads/issues.jsonl`."""
    issues = []
    if not path.exists():
        return []

    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            try:
                if line.strip():
                    issues.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return issues


def issue_has_label(issue: Dict, label: str) -> bool:
    """Handle label payload differences between legacy JSONL and Beads CLI output."""
    labels = issue.get("labels", []) or issue.get("label", [])
    if isinstance(labels, str):
        labels = [labels]
    return label in labels


def get_tech_plan(repo_root: Path, issue_id: str) -> Optional[str]:
    """Try to find a TECH_PLAN.md for the issue."""
    candidates = [
        repo_root / DOCS_DIR / issue_id / "TECH_PLAN.md",
        repo_root / DOCS_DIR / f"{issue_id}.md",
        repo_root / DOCS_DIR / issue_id / "INDEX.md",
    ]
    for p in candidates:
        if p.exists():
            return p.read_text(encoding="utf-8")
    return None


def construct_prompt(issue: Dict, tech_plan: Optional[str]) -> str:
    """Build the Mega-Prompt for Jules."""
    
    design_content = issue.get("design", "")
    if not design_content:
        design_content = "See TECH PLAN below."
        
    prompt = f"""
TASK: {issue['title']} (ID: {issue['id']})

DESCRIPTION:
{issue.get('description', '')}

DESIGN SPEC:
{design_content}

----------
TECH PLAN / DOCS:
{tech_plan if tech_plan else 'No external tech plan provided. Rely on Description and Design Spec.'}
----------

CRITICAL INSTRUCTIONS:
1. Implement exactly per the DESIGN SPEC above.
2. If the Spec is ambiguous, PAUSE and ask key questions (do not guess).

DEFINITION OF DONE (REQUIRED):
1. Create a reproduction test case (or new unit test).
2. Run `make ci-lite` (or standard test suite) and fix ALL failures.
3. If this is a UI feature, verify no console errors.
4. Your PR description must include a "Verification" section with test logs.
"""
    return prompt


def dispatch(issue: Dict, repo_name: str, repo_root: Path, dry_run: bool = True) -> bool:
    """Dispatch a single issue to Jules."""
    issue_id = issue['id']
    title = issue['title']
    
    print(f"🔍 Analyzing {issue_id}: {title}...")
    
    # 1. Fetch Context
    tech_plan = get_tech_plan(repo_root, issue_id)
    
    # 2. Build Prompt
    prompt = construct_prompt(issue, tech_plan)
    
    # 3. Construct Command
    cmd = [
        "jules", "remote", "new",
        "--repo", repo_name, 
        "--session", prompt,
    ]
    
    if dry_run:
        print(f"  [DRY RUN] Would execute:")
        print(f"  jules remote new --repo {repo_name} --session \"...\"")
        print(f"  [Prompt Length]: {len(prompt)} chars")
        return True

    try:
        print(f"🚀 Dispatching to Jules...")
        result = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
        )
        combined = (result.stdout or "") + "\n" + (result.stderr or "")

        if _looks_like_quota_error(combined):
            print(f"❌ Jules quota/rate-limit error detected while dispatching {issue_id}.")
            if combined.strip():
                print("---- Jules output ----")
                print(combined.rstrip())
                print("----------------------")
            print("Stopping further dispatches to avoid burning quota.")
            return False

        if result.returncode != 0:
            print(f"❌ Failed to dispatch {issue_id}. Exit code: {result.returncode}")
            if combined.strip():
                print("---- Jules output ----")
                print(combined.rstrip())
                print("----------------------")
            return False

        print(f"✅ Dispatched {issue_id} successfully.")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to dispatch {issue_id}. Error: {e}")
        return False
    except FileNotFoundError:
        print("❌ 'jules' CLI not found. Is it installed?")
        return False


def main():
    # Argument parsing
    parser = argparse.ArgumentParser(description="Cross-repo Jules Manager")
    parser.add_argument("--action", choices=["dispatch", "list", "pull"], default="dispatch", help="Action to perform")
    
    # Dispatch args
    parser.add_argument("--dry-run", action="store_true", help="[Dispatch] Print commands without executing")
    parser.add_argument("--force", action="store_true", help="[Dispatch] Ignore 'jules-ready' label check")
    parser.add_argument("--issue", type=str, help="[Dispatch] Dispatch specific issue only")
    parser.add_argument("--repo", type=str, help="Override auto-detected repo (owner/name)")
    parser.add_argument(
        "--max-sessions-per-run",
        type=int,
        default=0,
        help="[Dispatch] Max number of issues to dispatch in this run (0 = no limit)",
    )
    parser.add_argument(
        "--sleep-between",
        type=float,
        default=0.0,
        help="[Dispatch] Sleep N seconds between dispatches (helps avoid rate limits)",
    )
    
    # Pull args
    parser.add_argument("--session", type=str, help="[Pull] Session ID to pull")

    args = parser.parse_args()

    # Find repo root
    repo_root = find_repo_root()
    if not repo_root:
        print("❌ Error: Not in a git repository")
        sys.exit(1)
    
    # Get repo name
    repo_name = args.repo or get_repo_name()
    if not repo_name:
        print("❌ Error: Could not detect repo name. Use --repo owner/name")
        sys.exit(1)

    if args.action == "list":
        list_sessions(repo_name)
        return

    if args.action == "pull":
        if not args.session:
            print("❌ Error: --session ID required for pull action")
            sys.exit(1)
        pull_session(args.session, repo_root)
        return

    # Dispatch Logic
    print(f"📁 Repo: {repo_name}")
    print(f"📍 Root: {repo_root}")

    # Load issues
    issues = load_issues(repo_root)
    
    if not issues:
        print("❌ No issues found in Beads.")
        sys.exit(1)

    candidates = []

    # Filter
    for issue in issues:
        # If specific issue requested
        if args.issue:
            if issue.get("id") == args.issue:
                candidates.append(issue)
                break
            continue
        
        status = issue.get("status", "todo")
        is_ready = issue_has_label(issue, LABEL_TRIGGER)

        if status not in ["todo", "open", "in_progress"]:
            continue

        if not is_ready and not args.force:
            continue

        candidates.append(issue)

    if not candidates:
        if args.issue:
            print(f"❌ Issue {args.issue} not found.")
        else:
            print("No 'jules-ready' tasks found. Use --force to ignore label check.")
        return

    print(f"Found {len(candidates)} candidates.")
    if args.max_sessions_per_run and args.max_sessions_per_run > 0:
        candidates = candidates[: args.max_sessions_per_run]
        print(f"Limiting to {len(candidates)} candidates due to --max-sessions-per-run.")

    for idx, issue in enumerate(candidates):
        ok = dispatch(issue, repo_name, repo_root, dry_run=args.dry_run)
        if not ok:
            sys.exit(1)
        if args.sleep_between and idx < len(candidates) - 1:
            time.sleep(args.sleep_between)


def list_sessions(repo_name: str):
    """List active Jules sessions for the repo."""
    print(f"🔍 Checking Jules sessions for {repo_name}...")
    try:
        # Use standard list format
        subprocess.run(["jules", "remote", "list", "--session"], check=True)
        print("\n💡 To pull a session:")
        print("   python dispatch.py --action pull --session <ID>")
    except subprocess.CalledProcessError:
        print("❌ Failed to list sessions.")
    except FileNotFoundError:
        print("❌ 'jules' CLI not found.")


def pull_session(session_id: str, repo_root: Path):
    """Pull code from a Jules session and apply it to a feature branch."""
    print(f"📥 Pulling Session {session_id}...")
    
    # 1. Fetch Session Info to find Issue ID (Parsing stdout is tricky, maybe just prompt?)
    # For now, we will inspect the session diff to guess or just use a generic branch.
    # Actually, we can assume the user wants to apply it to CURRENT branch if they already checked it out,
    # OR we can try to be smart. 
    # Let's use 'feature-jules-<session_id>' if we can't find the ID, but 'feature-<issue_id>' if we can.
    
    # We'll just fetch and apply. The user (Agent) should handle branching before calling this if they want strict control.
    # BUT the strategy says "Create branch".
    
    branch_name = f"feature-jules-{session_id}"
    
    try:
        # Create branch
        print(f"🌿 Creating/Switching to branch {branch_name}...")
        subprocess.run(["git", "checkout", "-b", branch_name], check=False) # Helper, ignore error if exists
        subprocess.run(["git", "checkout", branch_name], check=True)
        
        # Pull and Apply
        print(f"⚡ applying patch...")
        subprocess.run(["jules", "remote", "pull", "--session", session_id, "--apply"], check=True)
        
        print("\n✅ Patch applied!")
        print("Next Steps:")
        print("1. Run `make ci-lite` to verify.")
        print("2. Commit and PR.")
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to pull session: {e}")

if __name__ == "__main__":
    main()
