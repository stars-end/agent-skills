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
import os
from pathlib import Path
from typing import List, Dict, Optional

# Constants
BEADS_FILE = ".beads/issues.jsonl"
DOCS_DIR = "docs"
LABEL_TRIGGER = "jules-ready"


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
    """Load all issues from the JSONL file."""
    issues = []
    beads_path = repo_root / BEADS_FILE
    
    if not beads_path.exists():
        print(f"❌ Error: Beads file not found at {beads_path}")
        return []
    
    with open(beads_path, "r") as f:
        for line in f:
            try:
                if line.strip():
                    issues.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return issues


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


def dispatch(issue: Dict, repo_name: str, repo_root: Path, dry_run: bool = True):
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
        return

    try:
        print(f"🚀 Dispatching to Jules...")
        subprocess.run(cmd, check=True)
        print(f"✅ Dispatched {issue_id} successfully.")
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to dispatch {issue_id}. Error: {e}")
    except FileNotFoundError:
        print("❌ 'jules' CLI not found. Is it installed?")


def main():
    parser = argparse.ArgumentParser(description="Cross-repo Jules Dispatcher")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without executing")
    parser.add_argument("--force", action="store_true", help="Ignore 'jules-ready' label check")
    parser.add_argument("--issue", type=str, help="Dispatch specific issue only")
    parser.add_argument("--repo", type=str, help="Override auto-detected repo (owner/name)")
    
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
        labels = issue.get("labels", [])

        if status not in ["todo", "open", "in_progress"]:
            continue
            
        is_ready = LABEL_TRIGGER in labels
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
    for issue in candidates:
        dispatch(issue, repo_name, repo_root, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
