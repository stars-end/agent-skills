# CLI Mastery & Environment Protocol

**Tags:** #tools #cli #railway #github #env

## 🚨 Environment Variable Protocol (CRITICAL)

**Core Rule:** Do NOT look for `.env` files.
We use **Railway** to inject secrets directly into the process environment.

**The "Trust the Shell" Invariant:**
1.  **Source of Truth:** The environment variables (`os.environ`, `process.env`) are the *only* source of truth.
2.  **Verification:** If you suspect a missing variable, run `railway run env | grep <VAR_NAME>`.
3.  **Prohibited:** Never create `.env` files to "fix" missing secrets. This causes leaks.

**How to Run Code:**
If your code fails with missing config, you are likely running "naked". Wrap it:
*   ❌ `python main.py`
*   ✅ `railway run python main.py`

---

## 🚅 Railway CLI (`railway`)

### 1. Context
*   **Check Environment:** `railway environment`
*   **List Services:** `railway service`

### 2. Diagnosis
Don't guess. Check the logs.
```bash
# Get the last 50 lines of logs
railway logs -n 50

# Check deployment status
railway up --detach
```

---

## 🐙 GitHub CLI (`gh`)

### 1. Reading State (JSON is King)
Always use `--json` to get structured data.

```bash
# List open PRs
gh pr list --json number,title,author,state

# Check CI/CD Run Status
gh run list --limit 5 --json conclusion,status
```

### 2. Actions
```bash
# Create a PR (Autofill from branch)
gh pr create --fill

# Checkout a PR
gh pr checkout 123
```

## 🧠 "Agentic" Workflow Example

**Bad Agent:** "I see a `.env` file is missing. I will create one."
**Good Agent:** "I need to run the backend. I will use `railway run python main.py` to ensure secrets are injected."
