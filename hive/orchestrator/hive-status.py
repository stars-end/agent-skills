#!/usr/bin/env python3
# hive/orchestrator/hive-status.py
import json
import os
import subprocess
import argparse
import concurrent.futures
import sys

def get_local_status():
    ledger_path = os.path.expanduser("~/.agent-hive/ledger.json")
    pods_dir = "/tmp/pods"
    
    if not os.path.exists(ledger_path):
        return {"host": "localhost", "status": "offline", "agents": []}
    
    try:
        agents = []
        if os.path.exists(pods_dir):
            for session in os.listdir(pods_dir):
                # Check if session is active (logs updating?)
                # For now just list them
                agents.append(session)
        return {"host": "localhost", "status": "online", "agents": agents}
    except Exception as e:
        return {"host": "localhost", "status": "error", "error": str(e)}

def get_remote_status(host):
    """
    Uses SSH to query a remote MagicDNS host for its Hive status.
    Requires 'jq' on remote or simple ls. We'll use simple ls for resilience.
    """
    try:
        # Check if pods dir exists and list it
        cmd = ["ssh", "-o", "ConnectTimeout=5", host, "ls -1 /tmp/pods 2>/dev/null"]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
        
        if res.returncode == 0:
            agents = [a for a in res.stdout.strip().split('\n') if a]
            return {"host": host, "status": "online", "agents": agents}
        else:
            return {"host": host, "status": "online (idle)", "agents": []}
            
    except subprocess.TimeoutExpired:
         return {"host": host, "status": "unreachable", "agents": []}
    except Exception as e:
        return {"host": host, "status": "error", "error": str(e)}

def main():
    parser = argparse.ArgumentParser(description="Hive Mind Swarm Status Dashboard")
    parser.add_argument("--nodes", help="Comma-separated list of MagicDNS hosts (e.g. 'runner-01,mac-mini')", default="")
    args = parser.parse_args()

    nodes = [n.strip() for n in args.nodes.split(',') if n.strip()]
    
    results = [get_local_status()]
    
    if nodes:
        print(f"📡 Scanning Swarm ({len(nodes)} remote nodes)...")
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            future_to_node = {executor.submit(get_remote_status, node): node for node in nodes}
            for future in concurrent.futures.as_completed(future_to_node):
                results.append(future.result())

    # Render Table
    print("\n" + "="*65)
    print(f"{ 'NODE':<25} | { 'STATUS':<15} | { 'AGENTS':<20}")
    print("-" * 65)
    
    for r in results:
        host = r.get('host', 'unknown')
        status = r.get('status', 'unknown')
        agents = r.get('agents', [])
        agent_count = len(agents)
        
        # Colorize
        status_str = status
        if status == "online":
            status_str = f"\033[32m{status}\033[0m"
        elif status == "unreachable":
            status_str = f"\033[31m{status}\033[0m"
            
        print(f"{host:<25} | {status_str:<24} | {agent_count} active")
        
    print("="*65 + "\n")

if __name__ == "__main__":
    main()
