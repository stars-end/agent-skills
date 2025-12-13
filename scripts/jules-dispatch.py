#!/usr/bin/env python3
"""
jules-dispatch.py - Dispatch Beads issues to Jules agents.

Usage:
  python3 jules-dispatch.py <issue-id>... [--dry-run]

Dependencies:
  - `bd` CLI (must be in PATH)
  - `jules` CLI (must be in PATH)
  - run from a directory where `bd` can resolve the project (or pass --project)
"""

import sys
import json
import subprocess
import argparse
import shlex
import os
from typing import List, Dict, Tuple

def get_beads_issue(issue_id: str) -> Dict:
    """Fetch issue details from Beads as JSON."""
    try:
        # We assume running from reliable context or relying on bd auto-discovery
        # For robustness, we might want to allow specifying the repo path if not CWD
        result = subprocess.run(
            ["bd", "show", issue_id, "--json"],
            capture_output=True,
            text=True,
            check=True
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error fetching issue {issue_id}: {e.stderr}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error parsing JSON for issue {issue_id}", file=sys.stderr)
        sys.exit(1)

def identify_context_skills(issue: Dict) -> List[str]:
    """
    Match context skills based on keywords.
    Simplified version of matching logic.
    """
    text = (issue.get("title", "") + " " + issue.get("description", "")).lower()
    skills = []
    
    mapping = {
        "context-database-schema": ["database", "schema", "migration", "sql", "table", "supabase"],
        "context-api-contracts": ["api", "endpoint", "rest", "route", "controller"],
        "context-ui-design": ["ui", "frontend", "css", "component", "react", "tailwind"],
        "context-infrastructure": ["ci", "railway", "deploy", "docker", "github actions"],
        "context-analytics": ["analytics", "tracking", "metrics"],
        "context-security-resolver": ["security", "resolver", "cusip", "isin", "symbol"],
        # Add more mappings as needed
    }

    for skill, keywords in mapping.items():
        if any(k in text for k in keywords):
            skills.append(skill)
            
    return skills if skills else ["area-context-create"] # Fallback

def generate_prompt(issue: Dict, skills: List[str]) -> str:
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

def main():
    parser = argparse.ArgumentParser(description="Dispatch Beads issues to Jules")
    parser.add_argument("issues", nargs="+", help="Beads issue IDs (e.g. bd-123)")
    parser.add_argument("--dry-run", action="store_true", help="Print command without executing")
    parser.add_argument("--repo", default=".", help="Repo path for Jules context")
    
    args = parser.parse_args()
    
    for issue_id in args.issues:
        print(f"Processing {issue_id}...")
        issue = get_beads_issue(issue_id)
        skills = identify_context_skills(issue)
        prompt = generate_prompt(issue, skills)
        
        cmd = [
            "jules", "remote", "new",
            "--repo", args.repo,
            "--session", prompt
        ]
        
        if args.dry_run:
            print(f"--- Dry Run {issue_id} ---")
            print(shlex.join(cmd))
            print("--- End Prompt ---")
        else:
            print(f"🚀 Dispatching {issue_id} to Jules...")
            try:
                subprocess.run(cmd, check=True)
                print(f"✅ Dispatched {issue_id}")
            except subprocess.CalledProcessError as e:
                print(f"❌ Failed to dispatch {issue_id}")

if __name__ == "__main__":
    main()
