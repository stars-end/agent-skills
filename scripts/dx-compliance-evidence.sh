#!/usr/bin/env bash
#
# dx-compliance-evidence.sh
#
# Generates a deterministic daily compliance evidence bundle.
# Handles local collection and remote (best-effort) collection.
#
set -euo pipefail

OUTPUT_DIR="$HOME/.dx-state/compliance"
mkdir -p "$OUTPUT_DIR"
JSON_OUT="$OUTPUT_DIR/latest.json"
MD_OUT="$OUTPUT_DIR/latest.md"

GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Host matrix with specific SSH targets
declare -A HOST_TARGETS=(
    ["macmini"]="local"
    ["homedesktop-wsl"]="fengning@homedesktop-wsl"
    ["epyc6"]="feng@epyc6"
)

LOCAL_HOSTNAME=$(hostname -s)

# Collector script - logic that runs on each host
# Outputs a raw JSON object for that host
COLLECTOR_SCRIPT=$(cat <<'EOF'
    echo "{ \"hostname\": \"$(hostname -s)\", \"jobs\": {"
    first=1
    # Check for job states
    if [ -d "$HOME/.dx-state" ]; then
        for f in "$HOME/.dx-state"/*.last_ok "$HOME/.dx-state"/*.last_fail; do
            if [ -f "$f" ]; then
                [ $first -eq 0 ] && echo ","
                name=$(basename "$f" | sed -E "s/\.(last_ok|last_fail)//")
                stat=$(basename "$f" | sed -E "s/.*\.last_//")
                ts=$(cat "$f")
                echo -n " \"$name\": { \"status\": \"$stat\", \"timestamp\": \"$ts\" }"
                first=0
            fi
        done
    fi
    echo "}, \"worktrees\": ["
    first=1
    # Check for worktrees
    if [ -d /tmp/agents ]; then
        # Use find to locate worktrees (limited to 20 for bounds)
        while IFS= read -r wt; do
            [ -z "$wt" ] && continue
            [ $first -eq 0 ] && echo ","
            id=$(basename "$(dirname "$wt")")
            repo=$(basename "$wt")
            lock_ts=0
            [ -f "$wt/.dx-session-lock" ] && lock_ts=$(cut -d: -f1 "$wt/.dx-session-lock" 2>/dev/null || echo 0)
            echo -n "{ \"id\": \"$id\", \"repo\": \"$repo\", \"lock_ts\": $lock_ts }"
            first=0
        done < <(find /tmp/agents -mindepth 3 -maxdepth 3 -name ".git" -exec dirname {} \; 2>/dev/null | sort | head -n 20)
    fi
    echo "] }"
EOF
)

TEMP_DIR=$(mktemp -d)

echo "Collecting compliance evidence from fleet..."

for host_key in "${!HOST_TARGETS[@]}"; do
    target="${HOST_TARGETS[$host_key]}"
    echo "  -> $host_key ($target)"
    
    if [[ "$target" == "local" ]]; then
        bash -c "$COLLECTOR_SCRIPT" > "$TEMP_DIR/$host_key.json" 2>/dev/null || echo "null" > "$TEMP_DIR/$host_key.json"
    else
        # Run remote collector via SSH
        ssh -o ConnectTimeout=3 "$target" "bash -c '$(echo "$COLLECTOR_SCRIPT" | sed "s/'/'\\\\''/g")'" > "$TEMP_DIR/$host_key.json" 2>/dev/null || echo "null" > "$TEMP_DIR/$host_key.json"
    fi
done

# Combine using Python for safety and determinism
python3 - <<EOF > "$JSON_OUT"
import json, os, sys

generated_at = "$GENERATED_AT"
temp_dir = "$TEMP_DIR"
host_keys = ["macmini", "homedesktop-wsl", "epyc6"]

res = {
    "schemaVersion": "v7.8-1",
    "generatedAtUtc": generated_at,
    "hosts": {}
}

for h in host_keys:
    p = os.path.join(temp_dir, h + ".json")
    try:
        if os.path.exists(p):
            with open(p) as f:
                content = f.read().strip()
                if content and content != "null":
                    res["hosts"][h] = json.loads(content)
                else:
                    res["hosts"][h] = {"status": "offline"}
        else:
            res["hosts"][h] = {"status": "missing"}
    except Exception as e:
        res["hosts"][h] = {"status": "error", "message": str(e)}

# Ensure deterministic output
print(json.dumps(res, indent=2, sort_keys=True))
EOF

# Generate Markdown Summary
python3 - <<EOF > "$MD_OUT"
import json
with open("$JSON_OUT") as f:
    d = json.load(f)

print(f"# DX Compliance Evidence Summary")
print(f"Generated: {d['generatedAtUtc']}\n")

for h in ["macmini", "homedesktop-wsl", "epyc6"]:
    hd = d["hosts"].get(h, {})
    print(f"## {h}")
    if "status" in hd:
        print(f"Status: {hd['status']}")
    else:
        print("| Job | Status | Last Run |")
        print("|---|---|---|")
        jobs = hd.get("jobs", {})
        if not jobs:
            print("| (none) | - | - |")
        else:
            for jname in sorted(jobs.keys()):
                j = jobs[jname]
                print(f"| {jname} | {j['status']} | {j['timestamp']} |")
        
        print("\n**Active Worktrees (Capped at 20):**")
        wts = hd.get("worktrees", [])
        if not wts:
            print("None")
        else:
            for wt in sorted(wts, key=lambda x: x['id']):
                print(f"- {wt['id']}/{wt['repo']} (lock: {wt['lock_ts']})")
    print()
EOF

rm -rf "$TEMP_DIR"
echo "✅ Compliance evidence bundle updated: $JSON_OUT"
