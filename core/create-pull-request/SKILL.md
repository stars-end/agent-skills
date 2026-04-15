---
name: create-pull-request
description: |
  Create GitHub pull request with atomic Beads issue closure. MUST BE USED for opening PRs.
  Asks if work is complete - if YES, closes Beads issue BEFORE creating PR.
  If NO, creates draft PR with issue still open. Automatically links Beads tracking and includes Feature-Key.
  Use when user wants to open a PR, submit work for review, merge into master, or prepare for deployment,
  or when user mentions "ready for review", "create PR", "open PR", "merge conflicts", "CI checks needed",
  "branch ahead of master", PR creation, opening pull requests, deployment preparation, or submitting for team review.
tags: [workflow, github, pr, beads, review]
allowed-tools:
  - Bash(bdx:*)
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(bd:*)
  - Bash(scripts/bd-*:*)
---

## Canonical bd prefix cutover (2026-04-02)

- `agent-skills` new-work Feature-Key / branch / PR metadata should use `bd-*`.
- Canonical Beads now defaults to `bd-*` for new issues, so the repo workflow and Beads default are aligned again.
- Legacy `af-*` or other historical prefixes may still resolve in Beads, but they are not the default contract for new `agent-skills` work.

# Create Pull Request

Open GitHub PR with Beads integration (<10 seconds total).

## Workflow

### 1. Extract and Validate Feature Key

```bash
CURRENT_BRANCH=$(git branch --show-current)

# Validate branch naming convention
# Allow dots for hierarchical IDs (e.g., feature-bd-xyz.1.2)
if [[ ! "$CURRENT_BRANCH" =~ ^feature-bd-[a-zA-Z0-9.-]+$ ]]; then
  echo "❌ Branch name doesn't follow convention"
  echo ""
  echo "Current branch: $CURRENT_BRANCH"
  echo "Expected format: feature-bd-<ID> (e.g., feature-bd-xyz or feature-bd-xyz.1.2)"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Recovery options:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Option 1: Rename branch to match Beads issue"
  echo "  1. Find your Beads issue:"
  echo "     bdx list --status open"
  echo ""
  echo "  2. Rename branch:"
  echo "     git branch -m feature-bd-<ID>"
  echo ""
  echo "  3. If pushed to remote:"
  echo "     git push origin :$CURRENT_BRANCH  # Delete old"
  echo "     git push -u origin feature-bd-<ID>  # Push new"
  echo ""
  echo "Option 2: Create Beads issue for current work"
  echo "  1. Extract descriptive name:"
  DESCRIPTIVE_NAME=$(echo "$CURRENT_BRANCH" | sed 's/^feature-//')
  echo "     Title: $DESCRIPTIVE_NAME"
  echo ""
  echo "  2. Create issue:"
  echo "     bdx create '$DESCRIPTIVE_NAME' --type feature --priority 2"
  echo "     # Returns: bd-xyz"
  echo ""
  echo "  3. Rename branch to match:"
  echo "     git branch -m feature-bd-xyz"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Why this matters:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "- Enables automatic PR-to-Beads linking"
  echo "- Provides commit history tracking via Feature-Key"
  echo "- Supports multi-developer coordination"
  echo "- Enforces Issue-First workflow"
  echo ""
  exit 1
fi

# Extract FEATURE_KEY from feature-bd-<ID> pattern
FEATURE_KEY=$(echo "$CURRENT_BRANCH" | sed 's/^feature-//')
```

**Why validate:**
- Enforces convention (feature-bd-xyz)
- Prevents silent failures downstream
- Provides clear recovery steps
- Educates on Issue-First workflow
- In `agent-skills`, this also guards against carrying `af-*` or any other non-`bd-*` Beads context into PR creation. Treat that mismatch as an early blocker and correct it before retrying.
- If you need a fresh tracking issue in `agent-skills`, create it explicitly as `bd-*` with `bdx create --id bd-<issue> --force` instead of relying on a generic default prefix.

### 2. Get Beads Context
Use the Beads context helper:
```bash
bd-context

# Get issue details
issue=$(bdx show <FEATURE_KEY> --json)
```

If not found, create proactively:
```bash
bdx create --title <FEATURE_KEY> --type feature --priority 2 --id <FEATURE_KEY>
```

**Detect epic vs feature:**
- If issue is epic → PR closes all child tasks, not epic itself
- If issue is feature → PR closes the feature directly
- Check: `issue.dependents` to find child tasks

### 2.3. Structural Verification (If Needed)
If `layout.tsx`, `middleware.ts`, or global config changed:
```bash
echo "ℹ️  Structural changes detected. Running build check..."
make build
if fails: exit 1
```

### 2.4. Verify Base Branch + Canonical Beads Health

**Before creating PR, ensure branch freshness and Beads availability:**

```bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔄 PRE-PR CHECKS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Fetch latest master/main to reduce merge conflict risk
git fetch origin master

# Optional: merge latest master now if behind
if ! git merge-base --is-ancestor origin/master HEAD; then
  echo "⚠️  Branch is behind origin/master. Merge/rebase before PR for cleaner review."
fi

# Canonical Beads health check
(beads-dolt dolt test --json && beads-dolt status --json)
```

**Why this is critical:**
- **Prevents avoidable PR conflicts:** catches branch drift early
- **Prevents false-ready PRs:** confirms tracker connectivity before closure/linking
- **Matches fleet contract:** uses Dolt backend checks with `BEADS_DIR=~/.beads-runtime/.beads`

### 2.5. Ask if Work is Complete (CRITICAL)

**Decision point:** Is work complete and ready to merge?

```bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 WORK COMPLETION CHECK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Is this work complete and ready to merge?"
echo ""
echo "✅ YES → Close Beads issue, create PR for merge"
echo "⏸️  NO  → Leave open, create draft PR for feedback"
echo ""
read -p "Complete? (y/n): " COMPLETE
echo ""
```

**If YES (work complete):**
```bash
# Close Beads issue BEFORE creating PR
echo "Closing Beads issue ${FEATURE_KEY}..."
bdx close ${FEATURE_KEY} --reason "Work complete, ready for review in PR"

# Verify canonical Beads health and push branch updates
(beads-dolt dolt test --json && beads-dolt status --json)
echo "Pushing feature branch updates..."
git push

echo ""
echo "✅ Issue closed in canonical Beads backend"
echo "✅ Feature branch pushed for review"
echo ""
```

**If NO (work in progress):**
```bash
# Leave issue as in_progress
echo "ℹ️  Keeping ${FEATURE_KEY} as in_progress"
echo "   → PR will be marked as draft"
echo ""

DRAFT_FLAG="--draft"
```

**Why this is critical:**
- **Deterministic state:** issue is explicitly marked done before review
- **No post-merge tracker work:** avoids merge-time bookkeeping drift
- **Clear workflow:** Close issue = "ready to ship", open issue = "work in progress"

### 2.6. Pre-PR Derived Artifact Freshness Check (Mandatory)

**Before creating any PR, agents MUST verify that derived artifacts are in sync.**

This check applies to ALL PRs — not just agent-skills, but any repo that consumes
generated outputs from agent-skills (AGENTS.md, universal-baseline.md, etc.).

```bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 DERIVED ARTIFACT FRESHNESS CHECK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
```

**Step 1: Check if agent-skills sources changed.**

If the PR modifies any of the following, derived artifacts MUST be regenerated:
- Any `SKILL.md` file under `core/`, `extended/`, `health/`, `infra/`, `railway/`, `dispatch/`
- `@NAKOMI.md`
- `scripts/publish-baseline.zsh`
- `Makefile` targets that affect baseline generation

```bash
CHANGED_SOURCES=$(git diff origin/master --name-only | \
  grep -E '(SKILL\.md$|@NAKOMI\.md$|publish-baseline\.zsh$)' || true)

if [ -n "$CHANGED_SOURCES" ]; then
  echo "⚠️  Source files changed that affect derived artifacts:"
  echo "$CHANGED_SOURCES" | sed 's/^/   /'
  echo ""
  echo "Running: make publish-baseline"
  make publish-baseline
  echo ""
fi
```

**Step 2: Check if docs or repo guidance changed.**

```bash
DOCS_CHANGED=$(git diff origin/master --name-only | \
  grep -E '^docs/' || true)

if [ -n "$DOCS_CHANGED" ]; then
  echo "ℹ️  Documentation files changed:"
  echo "$DOCS_CHANGED" | sed 's/^/   /'
  echo ""
fi
```

**Step 3: Verify freshness deterministically (agent-skills repo only).**

When working IN the agent-skills repo, run the freshness guard:

```bash
if [ -f "scripts/check-derived-freshness.sh" ]; then
  echo "Running derived artifact freshness check..."
  if ! bash scripts/check-derived-freshness.sh; then
    echo ""
    echo "❌ BLOCKED: Derived artifacts are stale."
    echo "   Run 'make publish-baseline' and commit the updated files before creating this PR."
    echo ""
    exit 1
  fi
fi
```

**Step 4: Self-check checklist (ALL repos).**

Before proceeding to PR creation, confirm:

| Check | Action if YES |
|-------|---------------|
| SKILL.md files changed? | Run `make publish-baseline` (agent-skills) or regenerate consuming outputs |
| docs/ changed? | Verify docs are complete and linked |
| @NAKOMI.md changed? | Run `make publish-baseline` |
| AGENTS.md appears stale? | Run `make publish-baseline` |
| No source changes? | Proceed (no regeneration needed) |

**Why this is critical:**
- **Prevents silent drift:** agents changing sources without updating derived outputs
- **Catches it at the chokepoint:** PR creation is the natural enforcement surface
- **Deterministic CI backing:** the `derived-freshness` CI job will fail on stale artifacts

### 2.7. Validate Docs (Epics/Features Only)

**Check if docs exist and are linked:**

```bash
DOC_DIR="docs/${FEATURE_KEY}"

if [ "$issue.type" = "epic" ] || [ "$issue.type" = "feature" ]; then
  # Check if docs directory exists
  if [ -d "$DOC_DIR" ]; then
    # Check if linked to Beads
    CURRENT_REF=$(bdx show ${FEATURE_KEY} --json | jq -r '.external_ref // ""')

    if [ -z "$CURRENT_REF" ] || [ "$CURRENT_REF" = "null" ]; then
      echo "ℹ️  Docs exist but not linked to Beads"
      echo "   Auto-linking: ${FEATURE_KEY} ↔ ${DOC_DIR}/"
      bdx update ${FEATURE_KEY} --external-ref "docs:${DOC_DIR}/"
    fi

    # Check if docs updated recently (within last 7 days)
    LAST_COMMIT=$(git log -1 --format=%at -- "$DOC_DIR")
    NOW=$(date +%s)
    DAYS_AGO=$(( ($NOW - $LAST_COMMIT) / 86400 ))

    if [ $DAYS_AGO -gt 7 ]; then
      echo ""
      echo "⚠️  Docs may be stale (last updated ${DAYS_AGO} days ago)"
      echo "   Consider reviewing: $DOC_DIR/"
      echo ""
    else
      echo "✅ Docs updated recently ($DAYS_AGO days ago)"
    fi
  else
    # No docs directory - informational only
    echo "ℹ️  No docs/ directory for ${FEATURE_KEY}"
    echo "   (OK for small features, recommended for epics)"
  fi
fi
```

**Why informational:**
- Non-blocking (doesn't prevent PR creation)
- Epics/features benefit from docs, but not required
- Tasks/bugs don't need separate docs
- User controls doc creation timing

**What this checks:**
- ✅ Docs exist? → Auto-link to Beads if not linked
- ✅ Docs recent? → Warn if stale (>7 days)
- ℹ️ No docs? → Informational (not error)

### 3. Push Branch
```bash
# Check if branch exists on remote
if ! git ls-remote --heads origin <branch>:
  git push -u origin <branch>
```

### 4. Create PR with gh CLI

**Prepare trailers:**
```bash
# Get agent identity
AGENT_ID="$(~/.agent/skills/scripts/get_agent_identity.sh)"
```

**Prepare doc link:**
```bash
DOC_DIR="docs/${FEATURE_KEY}"
if [ -d "$DOC_DIR" ]; then
  DOC_LINK="📄 Design docs: [`$DOC_DIR/`]($DOC_DIR/)"
else
  DOC_LINK="📄 No docs/ directory (tracked in Beads only)"
fi
```

**For Features:**
```bash
gh pr create 
  ${DRAFT_FLAG} 
  --title "{FEATURE_KEY}: Feature implementation" 
  --body "
## Feature

{FEATURE_KEY}

## Beads Issue

$(if [ -z "$DRAFT_FLAG" ]; then echo "Closes: bd-{ID}"; else echo "Related: bd-{ID} (in progress)"; fi)

Beads record: `bdx show bd-{ID}`

## Documentation

${DOC_LINK}

## Next Steps

- Dev environment: Auto-deploying
- CI checks: Running in background
- Review: $(if [ -z "$DRAFT_FLAG" ]; then echo "Ready once CI passes"; else echo "Ready when work complete"; fi)

---

## Trailers

Feature-Key: {FEATURE_KEY}
Agent: ${AGENT_ID}

---

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>
  " 
  --base master
```

**For Epics (closes child tasks, not epic):**
```bash
gh pr create 
  --title "{FEATURE_KEY}: Epic implementation" 
  --body "
## Epic

{FEATURE_KEY}

## Beads Issues

**This PR completes the following tasks:**
- Closes: bd-{ID}.1 (Research)
- Closes: bd-{ID}.2 (Spec)
- Closes: bd-{ID}.3 (Implementation)
- Closes: bd-{ID}.4 (Testing)

**Epic:** bd-{ID} (remains open for future work)

Beads record: `bdx show bd-{ID}`

## Documentation

${DOC_LINK}

## Next Steps

- Dev environment: Auto-deploying
- CI checks: Running in background
- Review: Ready once CI passes

---

## Trailers

Feature-Key: {FEATURE_KEY}
Agent: ${AGENT_ID}

---

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>
  " 
  --base master
```

### 5. Link PR to Beads
```bash
PR_NUMBER=$(gh pr view --json number -q .number)

# Use helper script if available
bd-link-pr $PR_NUMBER

# Or update via CLI
bdx update <FEATURE_KEY> status=in_progress --external-ref "PR#${PR_NUMBER}"
```

### 6. Confirm to User
```
✅ PR#{PR_NUMBER} created
✅ CI running in background
✅ Dev environment deploying

Check status: gh pr view {PR_NUMBER}
Test in dev: dev.yourapp.com/pr-{PR_NUMBER}
 ```

### 2.8. Frontend Evidence Contract (If Frontend Files Changed)

**When frontend files are modified in prime-radiant-ai, enforce evidence contract:**

```bash
# Check if frontend files changed
FRONTEND_CHANGES=$(git diff origin/master --name-only | grep -E "^frontend/" | head -1)

if [ -n "$FRONTEND_CHANGES" ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🎨 FRONTEND EVIDENCE CONTRACT"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Frontend changes detected. Before PR-ready:"
  echo ""
  echo "1. Run visual regression:"
  echo "   pnpm --filter frontend build"
  echo "   pnpm --filter frontend preview --port 5173 &"
  echo "   VISUAL_BASE_URL=http://localhost:5173 pnpm --filter frontend test:visual"
  echo ""
  echo "2. If baselines change, update and justify:"
  echo "   VISUAL_BASE_URL=http://localhost:5173 pnpm --filter frontend test:visual:update"
  echo ""
  echo "3. Add '## Frontend Evidence' section to PR body"
  echo ""
  echo "Template: ~/agent-skills/templates/frontend-evidence-contract.md"
  echo ""
fi
```

**Required PR body section for frontend changes:**

```markdown
## Frontend Evidence

### Route Matrix
| Route | Desktop | Mobile | Status |
|-------|---------|--------|--------|
| / | ✅ | ✅ | Pass |
| /sign-in | ✅ | ✅ | Pass |

### Runtime Health
- Console errors: 0
- Unexpected Application Error: No

### Evidence
- Commit SHA: [hash]
- Visual tests: [X] passed
- CI workflows: [links]
```

**CI will auto-run:**
- `visual-quality.yml` (Stylelint + Visual Regression)
- `lighthouse.yml` (Performance budgets)

**Why this matters:**
- Prevents false-positive "looks good" approvals
- Catches visual regressions before merge
- CI validates automatically - trust the pipeline

### 2.9. Prime V2 Product Contract (If V2 Routes/Stories Changed)

> ⚠️ **CRITICAL EXCEPTION**: For Prime `/v2` and `/brokerage`, visual evidence is **evidence only**.

**When PR touches V2 routes or contract docs, enforce product signoff:**

```bash
# Check if V2 routes/stories changed
V2_CHANGES=$(git diff origin/master --name-only | grep -E "(^frontend/src/(pages|routes|components)/(v2|brokerage)|^docs/TESTING/STORIES/production_v2/|^docs/v2/)" | head -1)

if [ -n "$V2_CHANGES" ]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "⚠️  V2 PRODUCT CONTRACT DETECTED"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "V2 product changes detected. Visual evidence is NOT sufficient."
  echo ""
  echo "REQUIRED before merge:"
  echo "1. Contract gate MUST pass:"
  echo "   make verify-v2-contract"
  echo ""
  echo "2. Founder live validation REQUIRED:"
  echo "   See: docs/v2/FOUNDER_SIGNOFF_FLOW.md"
  echo ""
  echo "3. Add V2 Product Signoff section to PR body (see below)"
  echo ""
  echo "Contract docs:"
  echo "  • docs/v2/PRODUCT_CONTRACT.md — Hard invariants"
  echo "  • docs/v2/RELEASE_GATE.md — Binary YES/NO checks"
  echo "  • docs/v2/FAKE_METRIC_GUARDRAILS.md — No demo/fake metrics"
  echo ""
fi
```

**Required V2 Product Signoff section for PR body:**

```markdown
## V2 Product Signoff Status

### Contract Gate
- [ ] `make verify-v2-contract` passed
- [ ] Contract artifacts: `artifacts/verification/contract/`

### Founder Live Validation
- [ ] Validation completed per `docs/v2/FOUNDER_SIGNOFF_FLOW.md`
- [ ] Routes validated: `/v2`, `/brokerage`

### Evidence vs Certification
| Evidence Type | Included | Can Certify V2? |
|---------------|----------|-----------------|
| Screenshots | ✅/❌ | ❌ NO |
| Style/lint | ✅/❌ | ❌ NO |
| Route health | ✅/❌ | ❌ NO |
| Contract gate | ✅/❌ | ✅ YES |
| Founder validation | ✅/❌ | ✅ YES |

### Contract Docs
- `docs/v2/PRODUCT_CONTRACT.md` — Hard invariants
- `docs/v2/RELEASE_GATE.md` — Binary YES/NO checks

⚠️ Visual evidence alone cannot certify V2 product correctness.
```

**Why V2 requires extra steps:**
- V2 has hard product invariants beyond visual correctness
- Real data vs demo data is a binary state that screenshots cannot verify
- Founder validation ensures business logic works with real holdings
- `verify-release` output "RELEASE NOT APPROVED YET" is intentional

 ## Best Practices

- **Create Beads issue if missing** - Never block on missing metadata
- **Use gh CLI** - More reliable than API calls
- **Link PR bidirectionally** - Beads → PR and PR → Beads
- **Trust async validation** - CI runs in background

## What Happens Next (Automatic)

- ✅ CI runs full test suite
- ✅ Dev environment auto-deploys PR
- ✅ GitHub posts check results
- ✅ Danger bot comments with guidance

**User can test immediately** in dev environment while CI runs.

## What This DOESN'T Do

- ❌ Wait for CI (runs async)
- ❌ Run tests locally (CI handles it)
- ❌ Validate deployment (environments handle it)

**Philosophy:** Fast PR creation + Trust the pipeline
