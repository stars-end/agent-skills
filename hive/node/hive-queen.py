import json, os, subprocess, time, uuid
def get_ready_beads():
    res = subprocess.run(["bd", "list", "--label", "hive-ready", "--format", "json"], capture_output=True, text=True)
    return json.loads(res.stdout) if res.returncode == 0 else []
def dispatch_agent(bead):
    session_id = str(uuid.uuid4())[:8]
    repos = bead.get('repos', ['prime-radiant-ai'])
    subprocess.run([os.path.expanduser("~/agent-skills/hive/pods/create.sh"), session_id, "--repos", ",".join(repos)])
    prompt = "Read context/00_MISSION.md. Implement task. Commit."
    unit_name = f"agent-{session_id}"
    agent_cmd = ["systemd-run", "--user", f"--unit={unit_name}", "--scope", "zsh", "-c", f"source ~/.zshrc && cc-glm -p '{prompt}'"]
    with open(f"/tmp/pods/{session_id}/logs/agent.log", "w") as f:
        subprocess.Popen(agent_cmd, cwd=f"/tmp/pods/{session_id}", stdout=f, stderr=subprocess.STDOUT)
    subprocess.run(["bd", "update", bead['id'], "--status", "in_progress"])
while True:
    for bead in get_ready_beads(): dispatch_agent(bead)
    time.sleep(60)
