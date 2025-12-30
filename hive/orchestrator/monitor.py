#!/usr/bin/env python3
# hive/orchestrator/monitor.py
import sys
import os
import time
import subprocess

def main():
    if len(sys.argv) < 2:
        print("Usage: hive-monitor <session_id> [host]")
        sys.exit(1)
        
    session_id = sys.argv[1]
    host = sys.argv[2] if len(sys.argv) > 2 else "localhost"
    
    print(f"🕵️  Tailing logs for session {session_id} on {host}...")
    
    log_path = f"/tmp/pods/{session_id}/logs/agent.log"
    
    if host == "localhost":
        cmd = ["tail", "-f", log_path]
    else:
        cmd = ["ssh", "-t", host, f"tail -f {log_path}"]
        
    try:
        subprocess.run(cmd)
    except KeyboardInterrupt:
        print("\nDisconnected.")

if __name__ == "__main__":
    main()

