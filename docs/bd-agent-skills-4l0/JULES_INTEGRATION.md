# Jules Integration

Three-gate routing to Jules cloud agent.

---

## Three-Gate Check

Jules dispatch requires **ALL THREE** conditions:

| Gate | Check | Why |
|------|-------|-----|
| 1 | `@jules` mention in message | Explicit intent |
| 2 | `jules-ready` label on Beads issue | Task is well-specified |
| 3 | `docs/bd-xxx/` spec directory exists | Detailed requirements |

---

## Routing Logic

```python
def should_route_to_jules(text: str, issue_id: str) -> bool:
    """Check if task should route to Jules."""
    
    # Gate 1: @jules mention
    if "@jules" not in text.lower():
        return False
    
    if not issue_id:
        return False
    
    # Gate 2: jules-ready label
    result = subprocess.run(
        ["bd", "show", issue_id, "--json"],
        capture_output=True, text=True
    )
    issue = json.loads(result.stdout)
    if "jules-ready" not in issue.get("labels", []):
        return False
    
    # Gate 3: docs/bd-xxx/ exists
    for repo in ["~/affordabot", "~/prime-radiant-ai"]:
        spec_path = os.path.join(repo, "docs", issue_id)
        if os.path.isdir(spec_path):
            return True
    
    return False
```

---

## Dispatch Flow

```
1. User: @jules bd-xyz implement the feature
2. Coordinator checks three gates
3. If all pass:
   → python3 jules-dispatch/dispatch.py bd-xyz --repo affordabot
4. Jules creates cloud session
5. Jules works on PR
6. Coordinator posts status to Slack thread
```

---

## Prompt Template

```python
JULES_PROMPT = """
You are Jules, a Google Cloud-based AI agent.

Task: {issue_title}
Issue ID: {issue_id}
Repo: {repo}

Specification:
{spec_content}

Instructions:
1. Read the spec in docs/{issue_id}/
2. Implement the changes
3. Create a PR with title: "{issue_id}: {pr_title}"
4. Update Beads status to closed

You have access to:
- Git for version control
- gh CLI for PR creation
- bd CLI for Beads updates
"""
```

---

## Error Handling

| Error | Cause | Action |
|-------|-------|--------|
| Gate 1 fail | No @jules mention | Route to local agent |
| Gate 2 fail | No jules-ready label | Post: "Add jules-ready label first" |
| Gate 3 fail | No spec directory | Post: "Create docs/bd-xxx/ spec first" |
| Dispatch fail | Jules CLI error | Post error, route to local |

---

## Status Updates

Jules posts to Slack thread:

```
[jules] Starting work on bd-xyz...
[jules] Created branch: feature-bd-xyz
[jules] Implementing: auth middleware
[jules] ✅ PR created: #42
```

---

## Testing

### Test Case 1: All Gates Pass

```bash
# Setup
bd create "Test Jules" --label jules-ready
mkdir -p ~/affordabot/docs/bd-test-jules

# Trigger
# Post to Slack: @jules bd-test-jules implement this

# Verify
# - Jules dispatch script called
# - PR created
```

### Test Case 2: Missing Label

```bash
# Setup (no jules-ready label)
bd create "Test Jules No Label"

# Trigger
# Post: @jules bd-test-nolabel implement this

# Verify
# - Error message posted
# - No dispatch
```

### Test Case 3: Missing Spec

```bash
# Setup (no docs/)
bd create "Test Jules No Spec" --label jules-ready

# Trigger
# Post: @jules bd-test-nospec implement this

# Verify
# - Error message: "Create docs/bd-xxx/ first"
```

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `JULES_DISPATCH_SCRIPT` | `~/agent-skills/jules-dispatch/dispatch.py` | Dispatch script |
| `JULES_TIMEOUT` | 30s | Dispatch timeout |

---

## Code Location

- Routing: `slack-coordinator.py:65-108`
- Dispatch: `jules-dispatch/dispatch.py`
- Config: `JULES_STRATEGY.md`
