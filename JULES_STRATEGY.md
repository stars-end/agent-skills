# Jules Automation Strategy for Beads Tasks

This document outlines the strategy for automatically assigning high-priority (P2+) Beads tasks to Jules agents.

## The Strategy: "Explicit Blessing" Bridge

We will link **Beads** and **Jules** using a **Scanner-Dispatcher** pattern.

### Core Philosophy: "No Implicit Dispatch"
To prevent vague prompts from wasting agent resources, we reject heuristic filtering (e.g., "description length > 200"). Instead, we require an **Explicit Signal**.

**The Rule:** Jules ONLY works on issues explicitly tagged with `jules-ready`.

### Workflow
1.  **Phase 1: Generally Human or Architect Agent**
    -   Creates Beads task.
    -   Writes `docs/bd-123/TECH_PLAN.md` (Optional but recommended).
    -   Fills `design` field in Beads.
    -   **Validation**: Runs `bd update bd-123 --add-label jules-ready`.
2.  **Phase 2: The Scanner (Gatekeeper)**
    -   Finds open `jules-ready` tasks.
    -   **Enforcement**: Checks for `design` content OR linked `docs/` file. If missing, removes label and comments "Spec missing".
3.  **Phase 3: The Dispatcher**
    -   Compiles the **Mega-Prompt**:
        -   Task Title & Description.
        -   Full `design` content.
        -   **CI Mandate**: Appends "Definition of Done".
    -   Invokes `jules remote new`.

## Addressing Quality (QA & CI)

### 1. Ensuring Specs are Followed
The Dispatcher injects a structured prompt:
```text
TASK: {title}
CONTEXT: {description}
DESIGN SPEC:
{design_field}
{tech_plan_content}

CRITICAL INSTRUCTIONS:
1. Implement exactly per the DESIGN SPEC above.
2. If the Spec is ambiguous, PAUSE and ask key questions (do not guess).
```

### 2. Ensuring CI/E2E
Every Jules session gets a strict **Definition of Done** appended:
```text
DEFINITION OF DONE (REQUIRED):
1. Create a reproduction test case (or new unit test).
2. Run `make ci-lite` (or standard test suite) and fix ALL failures.
3. If this is a UI feature, verify no console errors.
4. Your PR description must include a "Verification" section with test logs.
```

## Future Enhancements (Roadmap)

### 1. The "Spec-Writer" Pre-Pass (Reducing Human Toil)
The biggest bottleneck is writing the spec. We can automate this "Pre-Jules" step.
*   **Workflow**:
    1.  Human enters simple one-liner in Beads: "Update the tax loss harvesting logic to allow wash sale configuration."
    2.  **Spec Agent** (cheaper model) picks this up.
    3.  Reads codebase context and drafts `docs/bd-456/TECH_PLAN.md`.
    4.  Human **Reviews & Approves** (instead of writing from scratch).
    5.  Human tags `jules-ready`.

### 2. The "Test Sentinel" (Self-Healing CI)
Automate the fix for flaky or broken tests on `master`.
*   **Trigger**: GitHub Action detects failure on `master` (not PR).
*   **Dispatch**:
    *   **Prompt**: "The test `test_calculate_twr` failed on master. Here are the logs. Fix the flakiness."
    *   **Context**: Passes the failure log + relevant test file.

### 3. The "Dependency Steward"
*   **Trigger**: Weekly schedule.
*   **Action**: Runs `poetry update`, captures build/test failures.
*   **Dispatch**: "I updated `pydantic`. The build failed here. Please fix the breaking changes."

## Environment Setup (Critical)

Jules defaults to Python 3.12, but our project requires 3.13. We must align this using a setup script.

### 1. The Setup Script (`scripts/jules_setup.sh`)
Since your repo uses `mise` to lock versions (Python 3.13, Railway CLI, Node), we should just use that. This guarantees Jules has the **exact** same toolchain as your laptop.

Add this to `scripts/jules_setup.sh`:

```bash
#!/bin/bash
set -e

# 1. Install Mise (The one tool to rule them all)
if ! command -v mise &> /dev/null; then
    echo "🔧 Installing Mise..."
    curl https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"
    echo 'eval "$(mise activate bash)"' >> ~/.bashrc
    eval "$(mise activate bash)"
fi

# 2. Install All Tools (Python 3.13, Railway CLI, etc.) from .mise.toml
echo "📦 Installing Toolchain via Mise..."
mise install

# 3. Install Dependencies
echo "📦 Installing Project Dependencies..."
poetry install --no-interaction
pnpm install

# 4. Generate Mock Env (Safety)
echo "DB_HOST=localhost" > .env
echo "USE_MOCK_DATA=true" >> .env
```

### 2. Configure Jules Dashboard
1.  Go to **Configuration** > **Initial Setup**.
2.  Enter: `./scripts/jules_setup.sh`
3.  Click **Run and Snapshot**.

## Handling Secrets (The "GitHub-Like" Flow)

You are correctly using a Railway Service Token to sync secrets to GitHub. 

Jules, unlike GitHub Actions, does not have a "Secrets" tab that we can push to via API easily. However, we can trick it into behaving **exactly like your local runner**.

### The Solution: "Authenticate Once, Fetch Runtime"
Instead of copying 20+ variables into Jules, we only copy **ONE**: the `RAILWAY_TOKEN`.

1.  **Generate Service Token**: 
    -   Railway Dashboard → Settings → Tokens → "Jules Agent Token".
2.  **Add to Jules**:
    -   Jules Dashboard → Configuration → Environment Variables.
    -   Key: `RAILWAY_TOKEN`, Value: `(your-token-here)`.

### Updated Setup Script (`scripts/jules_setup.sh`)
Update the script to install the Railway CLI. Now Jules can run `railway run <command>` and it will automatically have access to all your secrets (DB URL, API Keys), just like your local shell.

```bash
# ... python setup ...
echo "🚂 Installing Railway CLI..."
npm install -g @railway/cli

# Now Jules can run: 
# railway run pytest (uses real secrets)
```
This perfectly mirrors your `scripts/setup-env-vars.sh` logic but handles authentication via the token env var.

## Comparison with Existing Skills

| Feature | Existing `jules-dispatch.py` | Proposed Strategy |
| :--- | :--- | :--- |
| **Trigger** | Manual CLI (`python jules-dispatch.py bd-123`) | Automated Batch (`python dispatch_cron.py`) |
| **Filtering** | None (user relies on judgment) | **Strict** (Label: `jules-ready`) |
| **Context** | Basic keyword matching | Enhanced Prompting (Design + AC) |
| **Use Case** | Validating a single task | Nightly "Batch Build" |

## Implementation Plan

1.  **Reuse Core**: Leverage `agent-skills/scripts/jules-dispatch.py` for the actual `jules remote ...` logic.
2.  **New Scanner**: Create `scripts/scan_and_dispatch.py` that implements the filtered loop.
3.  **Safety**: The scanner will verify `design` field presence as a secondary fail-safe.


## Prerequisites

1.  **Jules CLI Installed**:
    ```bash
    npm install -g @google/jules
    ```
2.  **Authenticated**:
    ```bash
    jules login
    ```
3.  **Repo Access**: Ensure the Jules GitHub App has access to `stars-end/prime-radiant-ai`.

## The Dispatch Script

We will create `scripts/dispatch_beads_to_jules.py` to handle the logic.

### Script Preview

```python
import json
import subprocess
import sys
from pathlib import Path

BEADS_FILE = Path(".beads/issues.jsonl")

def get_p2_issues():
    issues = []
    if not BEADS_FILE.exists():
        print(f"Error: {BEADS_FILE} not found.")
        return []
    
    with open(BEADS_FILE, "r") as f:
        for line in f:
            try:
                issue = json.loads(line)
                # Filter: Open + P2 or higher
                if issue.get("status") in ["todo", "open"] and issue.get("priority", 99) <= 2:
                    # Filter: Must be "specced out" (heuristic)
                    if issue.get("design") or len(issue.get("description", "")) > 200:
                        issues.append(issue)
            except json.JSONDecodeError:
                continue
    return issues

def dispatch_to_jules(issue):
    print(f"🚀 Dispatching {issue['id']}: {issue['title']}...")
    
    prompt = f"""
    Task: {issue['title']} (ID: {issue['id']})
    
    Description:
    {issue['description']}
    
    Design/Spec:
    {issue.get('design', 'N/A')}
    
    Please implement this task. Create a feature branch named 'feature-{issue['id']}'.
    """
    
    # Call Jules CLI
    # jules remote new --repo . --session "<prompt>"
    cmd = ["jules", "remote", "new", "--repo", ".", "--session", prompt]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(f"✅ Started Jules Session: {result.stdout.strip()}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to dispatch {issue['id']}: {e.stderr}")
        return False

def main():
    issues = get_p2_issues()
    print(f"Found {len(issues)} candidate P2+ issues.")
    
    for issue in issues:
        if dispatch_to_jules(issue):
            # Optional: Mark as assigned in Beads (requires CLI implementation)
            pass

if __name__ == "__main__":
    main()
```

## Phase 4: Retrieval & Integration (The "Pull Pattern")

Our experience shows that Cloud Agents often fail to push branches due to strict auth/permissions. To mitigate this, we adopt the **Pull Pattern**:

**Why?**
*   **Robustness**: Bypasses cloud git auth issues.
*   **Verification**: Allows local validation (`make ci-lite`) before pushing.
*   **Cleanliness**: Prevents broken code from polluting the remote.

**Workflow:**
1.  **Monitor**: Poll `jules remote list --session`.
2.  **Retrieve**: When status is "Completed":
    ```bash
    git checkout -b feature-123-jules
    jules remote pull --session <SESSION_ID> --apply
    ```
3.  **Verify**:
    ```bash
    make ci-lite
    ```
4.  **Ship**:
    ```bash
    git commit -am "feat: implement X (Jules Session <ID>)"
    gh pr create
    ```

This pattern treats Jules as a **Code Generator** rather than a fully autonomous committer. The Orchestration Agent (Antigravity) or Human acts as the **Integrator**.
