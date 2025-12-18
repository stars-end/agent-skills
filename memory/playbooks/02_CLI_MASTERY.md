# CLI Mastery: Railway & GitHub

**Tags:** #tools #cli #railway #github #automation

## 🚨 Core Mandate
**Do not ask the user to check status.** You have the tools. Use them.
*   **READ** commands (logs, status, list) -> **Run immediately.**
*   **WRITE** commands (deploy, merge, push) -> **Propose, then Run.**

## 🚅 Railway CLI (`railway`)

### 1. Context & Environment
*   **Check Environment:** `railway environment`
*   **List Services:** `railway service`
*   **Get Variables:** `railway variables` (Use with caution: secrets!)

### 2. Diagnosis (The "What's Wrong?" Loop)
Don't guess. Check the logs.
```bash
# Get the last 50 lines of logs for the current service
railway logs -n 50

# Check deployment status
railway up --detach # Triggers a build/deploy if needed
```

## 🐙 GitHub CLI (`gh`)

### 1. Reading State (JSON is King)
Always use `--json` to get structured data you can parse reliably.

```bash
# List open PRs
gh pr list --json number,title,author,url,state

# Check CI/CD Run Status (Crucial for debugging)
gh run list --limit 5 --json databaseId,status,conclusion,workflowName

# Read a specific issue
gh issue view 123 --json body,comments
```

### 2. Actions
```bash
# Create a PR (Autofill from current branch)
gh pr create --fill

# checkout a PR to test locally
gh pr checkout 123
```

## 🧠 "Agentic" Workflow Example

**Bad Agent:** "User, please check if the build failed."
**Good Agent:**
1.  Runs `gh run list --limit 1 --json conclusion`
2.  Sees `conclusion: failure`
3.  Runs `gh run view <id> --log-failed`
4.  Says: "The build failed due to a missing import in `main.py`. I am fixing it."
