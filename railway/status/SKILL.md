---
name: status
description: This skill should be used when the user asks "railway status", "is it running", "what's deployed", "deployment status", or about uptime. NOT for variables ("what variables", "env vars", "add variable") or configuration queries - use environment skill for those.
allowed-tools: Bash(railway:*), Bash(which:*), Bash(command:*)
---

# Railway Status

Check the current Railway project status for this directory.

## When to Use

- User asks about Railway status, project, services, or deployments
- User mentions deploying or pushing to Railway
- Before any Railway operation (deploy, update service, add variables)
- User asks about environments or domains

## When NOT to Use

Use the `environment` skill instead when user wants:
- Detailed service configuration (builder type, dockerfile path, build command, root directory)
- Deploy config (start command, restart policy, healthchecks, predeploy command)
- Service source (repo, branch, image)
- Compare service configs
- Query or change environment variables

## Check Status

Run:
```bash
railway status --json
```

First verify CLI is installed:
```bash
command -v railway
```

## Handling Errors

### CLI Not Installed
If `command -v railway` fails:

> Railway CLI is not installed. Install with:
> ```
> npm install -g @railway/cli
> ```
> or
> ```
> brew install railway
> ```
> Then authenticate: `railway login`

### Not Authenticated
If `railway whoami` fails:

> Not logged in to Railway. Run:
> ```
> railway login
> ```

### No Project Linked
If status returns "No linked project":

> No Railway project linked to this directory.
>
> **CRITICAL**: Agents must provide ALL required flags for non-interactive use:
> ```bash
> # CORRECT - Non-interactive
> railway link --project <id-or-name> --environment <env> --json
>
> # WRONG - Will block waiting for input
> railway link
> ```
>
> To create a new project: `railway init`
>
> Or for linking:
> ```bash
> railway link --project <id-or-name> --environment <env> [--service <service>] --json
> ```
>
> **NEVER run**: `railway link` (missing required flags)
>
> To create a new project: `railway init`

## Deployment Freshness ("Is master live?")

The authoritative answer to "is `origin/master` actually deployed?" comes from
**runtime**, not the Railway CLI. Use the shared helper from
`railway/_shared/scripts/railway-common.sh`:

```bash
source railway/_shared/scripts/railway-common.sh

# Preferred: runtime endpoint exposes commit SHA (header or body)
check_deploy_freshness --endpoint-url https://my-app.up.railway.app

# Fallback: Railway CLI deployment metadata only
check_deploy_freshness -p PROJECT_ID -e production -s web
```

The function outputs structured JSON:

```json
{
  "expected_sha": "abc1234...",
  "actual_sha": "abc1234...",
  "source": "runtime_header",
  "fresh": true,
  "drift": false
}
```

### Truth Hierarchy

| Priority | Source | `source` field | How |
|----------|--------|---------------|-----|
| 1a (preferred) | Response header `X-Commit-Sha` | `runtime_header` | `curl -D -` reads the header |
| 1b (next) | JSON body field | `runtime_body` | Parses `.commit`, `.sha`, `.git_commit`, or `.version.commit` from response body |
| 2 (fallback) | Railway CLI | `railway_cli` | `railway deployment list --json` — control-plane metadata, not runtime proof |

**Why runtime first:** The Railway CLI reports what was *deployed*, not what is *serving*.
Crash loops, partial rollouts, and cache layers can cause the CLI to show SUCCESS while
the live endpoint serves stale code. Only a runtime check confirms actual truth.

### How Product Repos Should Expose Commit Truth

Each deployed service should expose its build commit SHA in a way the freshness check
can read without application logic. The helper supports two mechanisms:

1. **Response header** (preferred, checked first): Set `X-Commit-Sha` in the HTTP server.
2. **JSON body**: Serve a JSON endpoint (e.g. `/commit-info`, `/version.json`, `/healthz`)
   that includes a `commit`, `sha`, `git_commit`, or `version.commit` field. The helper parses these
   keys in order and uses the first match.

To add a new body field key, extend the `jq` extraction chain inside the `# 1b:` block
of `check_deploy_freshness()` in `railway/_shared/scripts/railway-common.sh`.

## Presenting Status

Parse the JSON and present:
- **Project**: name and workspace
- **Environment**: current environment (production, staging, etc.)
- **Services**: list with deployment status
- **Active Deployments**: any in-progress deployments (from `activeDeployments` field)
- **Domains**: any configured domains
- **Freshness**: whether `origin/master` matches the live deployment (see above)

Example output format:
```
Project: my-app (workspace: my-team)
Environment: production
Freshness: origin/master (09a4ad5) matches live deployment

Services:
- web: deployed (https://my-app.up.railway.app)
- api: deploying (build in progress)
- postgres: running
```

The `activeDeployments` array on each service shows currently running deployments
with their status (building, deploying, etc.).
