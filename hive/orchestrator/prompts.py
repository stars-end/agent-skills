#!/usr/bin/env python3
# hive/orchestrator/prompts.py
import os
import json

def get_system_prompt(session_id, repos, mission_text):
    """
    Generates the 'Golden Path' system prompt for the agent.
    """
    prompt = f"""You are a Hive Mind Agent (ID: {session_id}).
You are running in a secure, isolated pod at /tmp/pods/{session_id}.

Available Worktrees:
{', '.join([f"- /tmp/pods/{session_id}/worktrees/{r}" for r in repos])}

Operational Guidelines:
1. Understand: Read context/00_MISSION.md and context/02_MEMORY.md (if exists).
2. Act: Perform the requested task in the appropriate worktree.
3. Verify: Run tests or validation scripts.
4. Commit: Use 'git commit' with a clear message. Do NOT push.
5. Exit: When done, summarize your work and exit.

Safety:
- You are running in a git worktree. Your changes are isolated.
- Do NOT attempt to access files outside the pod or your worktrees.

YOUR MISSION:
{mission_text}
"""
    return prompt

def prepare_briefcase(pod_dir, mission_text, memory_text=""):
    """
    Writes the mission and memory context to the pod's briefcase.
    """
    mission_path = os.path.join(pod_dir, "context", "00_MISSION.md")
    memory_path = os.path.join(pod_dir, "context", "02_MEMORY.md")
    
    with open(mission_path, "w") as f:
        f.write(mission_text)
        
    if memory_text:
        with open(memory_path, "w") as f:
            f.write(memory_text)
            
    print(f"💼 Briefcase prepared at {mission_path}")
