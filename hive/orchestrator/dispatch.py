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

    # Load secrets from environment (fail fast if not set)
    anthropic_token = os.environ.get("ANTHROPIC_AUTH_TOKEN")
    if not anthropic_token:
        raise RuntimeError("ANTHROPIC_AUTH_TOKEN must be set in environment. Load from 1Password: op run -- python3 ...")

    anthropic_base_url = os.environ.get("ANTHROPIC_BASE_URL", "https://api.z.ai/api/anthropic")

    with open(wrapper_path, "w") as f:
        f.write(f"""#!/usr/bin/env zsh
# Auto-generated Hive Agent Wrapper
# Secrets injected from environment (loaded via op run or 1Password)
export PATH="/home/feng/.local/bin:/usr/local/bin:/usr/bin:/bin"
export ANTHROPIC_AUTH_TOKEN="{anthropic_token}"
export ANTHROPIC_BASE_URL="{anthropic_base_url}"
export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-4.7"
export ANTHROPIC_DEFAULT_SONNET_MODEL="glm-4.7"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-4.7"
export API_TIMEOUT_MS="3000000"

# Execute Claude Code headlessly
# We use -p for non-interactive and --dangerously-skip-permissions for autonomy
claude --dangerously-skip-permissions --model glm-4.7 -p "$1"
""")
    os.chmod(wrapper_path, 0o755)

    # We use systemd-run to launch the agent as a background service.
    # We use 'script' to provide a fake TTY and tell it to write directly to our log file.
    agent_cmd = [
        "systemd-run",
        "--user",
        f"--unit={unit_name}",
        "--description=Hive Agent Session",
        "script", "-q", "-e", "-c", f"{wrapper_path} '{safe_prompt}'", log_path
    ]
    
    print(f"🚀 Dispatching Agent {session_id}...")
    subprocess.run(agent_cmd, check=True)
    
    return 0

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: dispatch.py <session_id> <prompt>")
        sys.exit(1)
    run_agent(sys.argv[1], sys.argv[2])
