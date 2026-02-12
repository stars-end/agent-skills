# Environment Sources Contract (V5.0)

## Core Principle: Environment Context Required for Dev Work

**All development work requires environment context.** This means:

1. **DX/dev workflow secrets** (agent keys, automation tokens) are sourced from 1Password (`op://` references)
2. **Project-specific runtime context** varies by project - some use Railway, others use different platforms
3. **Verification tasks** require the appropriate environment context for the target platform

**Key Insight:** "op-only" means 1Password is the source of truth for secrets, NOT that Railway context is irrelevant. Verification tasks that check deployed services require Railway (or other platform) context in addition to secrets.

## Purpose

This contract defines the sources of environment configuration and explicitly maps task types to required sources. It enforces **platform hard-fail semantics only when platform context is expected**, preventing false positives in local development.

## Three Sources of Truth

### 1. op-only (1Password Secrets)
**Definition**: Secrets sourced via `op://` references or `op run --` injection
**Scope**: Local development, systemd services, any environment where 1Password CLI is available
**Access Pattern**:
```bash
# Direct op:// reference in config files (per-service items)
SLACK_BOT_TOKEN=op://dev/Slack-Coordinator-Secrets/SLACK_BOT_TOKEN
ANTHROPIC_AUTH_TOKEN=op://dev/Anthropic-Config/ANTHROPIC_AUTH_TOKEN

# OR op run wrapper
op run --env-file=.env -- command-that-needs-secrets
```

**Guardrails**:
- ✅ Allowed: `op://` references in checked-in files
- ❌ Forbidden: Hardcoded secret values (triggers secret-scan.sh)
- ❌ Forbidden: `op run -- --no-masking` (triggers op-guardrail.sh)

### 2. Railway CLI Login (Authenticated Session)
**Definition**: Railway access via interactive CLI authentication session
**Scope**: Manual deployment operations, developer-initiated workflows
**Access Pattern**:
```bash
# Interactive login (once per session)
railway login

# Subsequent commands inherit session
railway up
railway logs
railway status
```

**Guardrails**:
- ⚠️ Hard-fail DISABLED: Optional check only (may not be logged in during local dev)
- ✅ Usage: Deployments, manual diagnostics, release workflows

### 3. Railway Shell Context (Explicit RAILWAY_TOKEN)
**Definition**: Railway access via exported `RAILWAY_TOKEN` environment variable
**Scope**: CI/CD pipelines, automated deployment workflows, scripts requiring non-interactive access
**Access Pattern**:
```bash
# Export token for script session
export RAILWAY_TOKEN=$(op item get --vault dev "Railway-Delivery" --fields label="token")
railway up  # Uses exported token, not interactive session
```

**Guardrails**:
- ⚠️ Hard-fail ENABLED: Script must fail if RAILWAY_TOKEN not set when required
- ✅ Usage: CI/CD, automated workflows, any non-interactive Railway operation

## Project-Specific Environment Sources

Different projects use different runtime platforms. This contract defines the general patterns; project-specific docs provide implementation details.

| Project | Primary Platform | Secrets Source | Runtime Context Source |
|---------|-----------------|----------------|----------------------|
| `agent-skills` | Railway | 1Password (`op://`) | Railway CLI / `RAILWAY_TOKEN` |
| `prime-radiant-ai` | Railway | 1Password (`op://`) | Railway CLI / `RAILWAY_TOKEN` |
| `affordabot` | Railway | 1Password (`op://`) | Railway CLI / `RAILWAY_TOKEN` |
| `llm-common` | (library, no deploy) | 1Password (`op://`) | N/A |

**Important:** When running `verify-*` tasks for Railway-deployed projects, you need BOTH:
1. 1Password access (for secrets like `ANTHROPIC_AUTH_TOKEN`)
2. Railway context (for querying deployed services)

See project-specific docs for detailed configuration.

## Task-to-Source Mapping

| Task Type | Required Source(s) | Railway Hard-Fail? |
|-----------|-------------------|-------------------|
| **Local Development (No Platform Access Needed)** | | |
| Running unit tests locally | op-only | ❌ No |
| Local MCP server startup | op-only | ❌ No |
| IDE-based agent workflows | op-only | ❌ No |
| Local script development | op-only | ❌ No |
| **Platform Verification (Requires Platform Context)** | | |
| `verify-pipeline` for Railway projects | op-only + Railway context | ⚠️ Warn (needs Railway for full check) |
| Checking deployment status | Railway CLI login | ❌ No (optional) |
| Viewing deployment logs | Railway CLI login | ❌ No (optional) |
| **Manual Deployments** | | |
| `railway up` (interactive) | Railway CLI login | ❌ No |
| **Automated Workflows** | | |
| CI/CD deployment | Railway shell context | ✅ Yes (must have RAILWAY_TOKEN) |
| `scripts/deploy.sh` | Railway shell context | ✅ Yes (must have RAILWAY_TOKEN) |
| Automated status checks | Railway shell context | ✅ Yes (must have RAILWAY_TOKEN) |
| **Systemd Services** | | |
| opencode.service | op-only (LoadCredentialEncrypted) | N/A |
| slack-coordinator.service | op-only (LoadCredentialEncrypted) | N/A |

### Clarification: op-only vs Platform Context

- **op-only**: Task only needs secrets from 1Password (e.g., local unit tests that mock external services)
- **op-only + Platform context**: Task needs both secrets AND platform access (e.g., verify-pipeline checks deployed service health)
- **"op-only" does NOT mean "platform is irrelevant"** - it means 1Password is the secrets source, but the task may still need platform-specific context

## Implementation Rules

### Rule 1: Explicit Declaration
Scripts MUST declare their environment source requirements:
```bash
#!/usr/bin/env bash
# ENV_SOURCES: op-only, Railway shell context
set -euo pipefail

# Fail hard if Railway token required but not set
if [[ -z "${RAILWAY_TOKEN:-}" ]]; then
    echo "ERROR: RAILWAY_TOKEN must be set for this script" >&2
    echo "Load from 1Password: export RAILWAY_TOKEN=\$(op item get ...)" >&2
    exit 1
fi
```

### Rule 2: Guardrail Integration
Railway hard-fail checks MUST respect the env-sources contract:
```bash
# In mcp-doctor/check.sh or Railway verification scripts
SCRIPT_MODE="${SCRIPT_MODE:-unknown}"

case "$SCRIPT_MODE" in
    "local-dev"|"interactive")
        # Railway check is optional (may not be logged in)
        railway_check_mode="optional"
        ;;
    "ci-cd"|"automated")
        # Railway check is mandatory (must have RAILWAY_TOKEN)
        railway_check_mode="required"
        ;;
esac
```

### Rule 3: Secret Loading
Scripts MUST use 1Password for secrets, NEVER hardcode:
```bash
# CORRECT: Load from 1Password
ANTHROPIC_AUTH_TOKEN=$(op item get --vault dev "Anthropic-Config" --fields label="ANTHROPIC_AUTH_TOKEN")

# CORRECT: Use op run for multiple secrets
op run --env-file=.env -- python3 script.py

# WRONG: Hardcoded (triggers secret-scan.sh)
ANTHROPIC_AUTH_TOKEN="your-hardcoded-token-here"  # NEVER DO THIS
```

## Verification

### Manual Verification Checklist
- [ ] Script declares ENV_SOURCES in header comment
- [ ] Script fails hard when Railway shell context required but missing
- [ ] Script uses op:// or op run for ALL secrets
- [ ] Script contains NO hardcoded secret values (verify with `secret-scan.sh --fail`)

### Automated Verification
```bash
# Run secret scan on repo
~/agent-skills/scripts/guardrails/secret-scan.sh --fail

# Check Railway token handling in scripts
grep -r "RAILWAY_TOKEN" scripts/ | grep -v "op://"
```

## Migration Notes

### V4.2.1 → V5.0 Changes
- **Added**: Core principle section clarifying "environment context required for dev work"
- **Added**: Project-specific table showing different projects use different platforms
- **Clarified**: Distinction between "op-only" (secrets source) and platform context (runtime access)
- **Fixed**: Task mapping now correctly shows verify-* tasks need platform context
- **Generalized**: Language now applies to any platform, not just Railway-specific

### V4.1 → V4.2.1 Changes
- **Before**: Railway checks always hard-failed (false positives in local dev)
- **After**: Railway checks respect env-sources contract (hard-fail only in shell context mode)

### Breaking Changes
None. This is a **contract clarification**, not a breaking change. Existing scripts continue to work but should be updated to declare their ENV_SOURCES.

## References

- **Related Docs**:
  - `~/agent-skills/docs/SECRET_MANAGEMENT.md` - 1Password secret management patterns
  - `~/agent-skills/docs/SERVICE_ACCOUNTS.md` - Service account architecture
  - `~/agent-skills/docs/1PASSWORD_MULTI_ITEM_ARCHITECTURE.md` - Per-service item design
- **Guardrails**:
  - `~/agent-skills/scripts/guardrails/secret-scan.sh` - Secret scanning
  - `~/agent-skills/scripts/guardrails/op-guardrail.sh` (TODO) - OP_RUN_NO_MASKING detection
- **Beads Issue**: `bd-dx83.8` - Env sources contract V5.0 update
