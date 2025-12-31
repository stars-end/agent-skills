#!/usr/bin/env python3
# hive/orchestrator/dispatch.py
import subprocess
import os
import sys

def run_agent(session_id, system_prompt):
    """
    Executes the agent using systemd-run and the cc-glm wrapper.
    """
    pod_dir = f"/tmp/pods/{session_id}"
    log_path = os.path.join(pod_dir, "logs", "agent.log")
    unit_name = f"hive-agent-{session_id}"
    
    # Escape single quotes for shell safety
    safe_prompt = system_prompt.replace("'", "'\\''")
    
    # Create a wrapper script inside the pod to handle environment and execution
    wrapper_path = os.path.join(pod_dir, "run_agent.sh")
    with open(wrapper_path, "w") as f:
        f.write(f"""#!/usr/bin/env zsh
# Auto-generated Hive Agent Wrapper
export ANTHROPIC_AUTH_TOKEN="42d8398609024e4b8ed68895a3feabdd.14a8um9X0PiC49iZ"
export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-4.7"
export ANTHROPIC_DEFAULT_SONNET_MODEL="glm-4.7"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-4.7"
export API_TIMEOUT_MS="3000000"

# Execute Claude Code headlessly
# We use -p for non-interactive and --dangerously-skip-permissions for autonomy
claude --dangerously-skip-permissions --model glm-4.7 -p "$1"
""")
    os.chmod(wrapper_path, 0o755)

    # We use zsh -c to run the wrapper via 'script' to provide a fake TTY
    agent_cmd = [
        "systemd-run",
        "--user",
        f"--unit={unit_name}",
        "--description=Hive Agent Session",
        "--scope",
        "script", "-q", "-e", "-c", f"{wrapper_path} '{safe_prompt}'", "/dev/null"
    ]
    
    print(f"🚀 Dispatching Agent {session_id}...")
    
    with open(log_path, "w") as f:
        # We start the process and let it run in the background via systemd-run --scope
        # Actually, --scope is synchronous, but systemd-run --unit=... would be background.
        # We want it to be asynchronous so the Queen can keep polling.
        # But we also want to capture the output.
        
        # Change cwd to the primary worktree if possible
        worktrees_dir = os.path.join(pod_dir, "worktrees")
        cwd = pod_dir
        if os.path.exists(worktrees_dir):
            dirs = os.listdir(worktrees_dir)
            if dirs:
                cwd = os.path.join(worktrees_dir, dirs[0])

        process = subprocess.Popen(
            agent_cmd,
            stdout=f,
            stderr=subprocess.STDOUT,
            cwd=cwd,
            preexec_fn=os.setsid
        )
        
    return process.pid

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: dispatch.py <session_id> <prompt>")
        sys.exit(1)
    run_agent(sys.argv[1], sys.argv[2])
