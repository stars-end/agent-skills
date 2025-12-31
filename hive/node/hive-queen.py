#!/usr/bin/env python3
# hive/node/hive-queen.py
# The Autonomous Dispatcher: Polls Beads, Prepares Context, and Spawns Agents.

import json
import os
import subprocess
import time
import uuid
import sys

# Import Orchestrator components
sys.path.append(os.path.expanduser("~/agent-skills/hive/orchestrator"))
try:
    import prompts
    import dispatch
except ImportError:
    # Fallback if pathing is weird during testing
    pass

def get_ready_beads():
    """Polls Beads for issues labeled 'hive-ready'."""
    try:
        res = subprocess.run(["bd", "list", "--label", "hive-ready", "--json"], 
                             capture_output=True, text=True)
        if res.returncode == 0:
            output = res.stdout.strip()
            if not output: return []
            try:
                return json.loads(output)
            except json.JSONDecodeError:
                print(f"⚠️  Invalid JSON from beads: {output}")
                return []
    except Exception as e:
        print(f"Error polling beads: {e}")
    return []

def dispatch_bead(bead):
    """Workflow for a single task."""
    session_id = str(uuid.uuid4())[:8]
    repos = bead.get('repos', ['agent-skills'])
    if isinstance(repos, str): repos = [repos]
    
    print(f"🐝 Found Task: {bead['id']} - {bead['title']}")
    
    # 1. Create Pod
    create_script = os.path.expanduser("~/agent-skills/hive/pods/create.sh")
    subprocess.run([create_script, session_id, ",".join(repos)], check=True)
    
    pod_dir = f"/tmp/pods/{session_id}"
    
    # 2. Prepare Context (Cass search)
    mission = f"Task: {bead['title']}\n\nDescription: {bead.get('description', 'No description provided.')}"
    
    # Attempt to fetch memory via Cass
    memory = ""
    try:
        search_query = f"{bead['title']} {bead.get('description', '')}"[:200]
        res = subprocess.run(["cass", "search", search_query, "--limit", "3"], 
                             capture_output=True, text=True)
        if res.returncode == 0:
            memory = res.stdout
    except:
        pass
        
    import prompts
    prompts.prepare_briefcase(pod_dir, mission, memory)
    
    # 3. Dispatch Agent
    system_prompt = prompts.get_system_prompt(session_id, repos)
    
    import dispatch
    dispatch.run_agent(session_id, system_prompt)
    
    # 4. Update Bead Status
    subprocess.run(["bd", "update", bead['id'], "--status", "in_progress"], check=True)
    print(f"✅ Dispatched {session_id} for {bead['id']}")

def sync_repo():
    """Pulls the latest changes from the remote to see new tasks."""
    try:
        # We only pull if the repo is clean to avoid conflicts
        subprocess.run(["git", "pull", "--rebase", "--autostash"], 
                       cwd=os.path.expanduser("~/agent-skills"),
                       capture_output=True, check=True)
    except Exception as e:
        # Don't crash on network blips, just log
        print(f"⚠️  Sync failed: {e}")

def main():
    print("🐝 Hive Queen is alive and polling...")
    while True:
        sync_repo() # Sync state from git (The Hive Mind)
        beads = get_ready_beads()
        for bead in beads:
            try:
                dispatch_bead(bead)
            except Exception as e:
                print(f"❌ Failed to dispatch {bead['id']}: {e}")
        
        time.sleep(30) # Poll every 30s

if __name__ == "__main__":
    main()