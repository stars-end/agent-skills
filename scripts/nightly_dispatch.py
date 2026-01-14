#!/usr/bin/env python
"""
nightly_dispatch.py - Run nightly verification on fleet

Dispatches verification tasks to the fleet using lib/fleet with 'nightly' mode.
"""

import sys
import time
import argparse
from datetime import datetime
from pathlib import Path

# Add agent-skills root to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.fleet import FleetDispatcher, DispatchResult

REPOS = ["prime-radiant-ai", "affordabot"]
VM_PREFERENCE = "epyc6"  # Prefer powerful machine for nightly runs

def log(msg: str):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")

def main():
    parser = argparse.ArgumentParser(description="Run nightly verification")
    parser.add_argument("--dry-run", action="store_true", help="Don't actually dispatch")
    parser.add_argument("--repo", action="append", help="Specific repos to verify (default: all)")
    args = parser.parse_args()

    repos = args.repo or REPOS
    dispatcher = FleetDispatcher()
    
    log(f"🌙 Starting Nightly Dispatch for: {', '.join(repos)}")
    log(f"   Mode: nightly (longer timeouts)")
    log(f"   Target: {VM_PREFERENCE}")

    results = []

    for repo in repos:
        beads_id = f"nightly-{repo}-{datetime.now().strftime('%Y%m%d-%H%M')}"
        prompt = (
            f"Run nightly verification for {repo}.\n"
            f"Command: make verify-pipeline && echo 'VERIFICATION_SUCCESS'"
        )

        if args.dry_run:
            log(f"[DRY-RUN] Would dispatch to {repo}: {beads_id}")
            continue

        log(f"Dispatching {repo} ({beads_id})...")
        try:
            result = dispatcher.dispatch(
                beads_id=beads_id,
                prompt=prompt,
                repo=repo,
                mode="nightly",
                preferred_backend=VM_PREFERENCE
            )
            
            if result.success:
                log(f"✅ Dispatched {repo}: Session {result.session_id} on {result.backend_name}")
                results.append((repo, result.session_id))
            else:
                log(f"❌ Failed to dispatch {repo}: {result.error}")
        except Exception as e:
            log(f"❌ Error dispatching {repo}: {e}")

    if args.dry_run:
        return

    # Wait for completion
    log("\n⏳ Waiting for results...")
    failures = 0
    passed = 0

    for repo, session_id in results:
        log(f"Polling {repo} ({session_id})...")
        status = dispatcher.wait_for_completion(
            session_id, 
            poll_interval_sec=30, 
            max_polls=120  # 1 hour max wait
        )
        
        final_status = status.get("status")
        if final_status == "completed":
            log(f"✅ {repo}: Passed")
            passed += 1
        else:
            log(f"❌ {repo}: Failed/Timeout ({final_status})")
            if status.get("failure_code"):
                log(f"   Code: {status.get('failure_code')}")
            failures += 1

    log(f"\n📊 Summary: {passed} passed, {failures} failed")
    
    if failures > 0:
        sys.exit(1)

if __name__ == "__main__":
    main()
