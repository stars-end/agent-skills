# Frontend Evidence Contract

> **Purpose:** Prevent false-positive UI/UX handoffs by enforcing standard evidence requirements for frontend PRs.
> **Version:** 1.1 (bd-4n6s - synced with PR #877)

## Agent Workflow for Frontend Changes

When you modify frontend files, follow this workflow:

### Step 1: Make Changes
```bash
# Work in worktree
dx-worktree create bd-xxxx prime-radiant-ai
cd /tmp/agents/bd-xxxx/prime-radiant-ai
```

### Step 2: Build and Verify Locally
```bash
# Build frontend
pnpm --filter frontend build

# Run type check
pnpm --filter frontend type-check

# Run stylelint (design token enforcement)
pnpm --filter frontend lint:css
```

### Step 3: Run Visual Regression
```bash
# Start preview server
pnpm --filter frontend preview --port 5173 &

# Wait for server
sleep 3

# Run visual tests (requires VISUAL_BASE_URL to skip webServer startup)
VISUAL_BASE_URL=http://localhost:5173 pnpm --filter frontend test:visual
```

### Step 4: If Visual Tests Fail
```bash
# Check if change is intentional
# If intentional, update baselines:
VISUAL_BASE_URL=http://localhost:5173 pnpm --filter frontend test:visual:update

# Commit new baselines with justification
git add frontend/e2e/visual/__snapshots__/
```

### Step 5: Include Evidence in PR
Add `## Frontend Evidence` section to PR body (see template below).

---

## Route Matrix (Required)

Test routes relevant to your changes:

| Route | Desktop | Mobile | Notes |
|-------|---------|--------|-------|
| `/` | ✅/❌ | ✅/❌ | Landing page |
| `/sign-in` | ✅/❌ | ✅/❌ | Auth screen |
| `/sign-up` | ✅/❌ | - | Auth screen |
| `/v2` | ✅/❌ | - | Requires auth bypass |
| `/brokerage` | ✅/❌ | - | Requires auth bypass |

---

## Runtime Health Checks (Required)

### Error Pattern Detection

The following patterns must NOT appear in console or page:

| Pattern | Level | Action |
|---------|-------|--------|
| `Unexpected Application Error` | 🔴 Blocking | PR cannot proceed |
| `ClerkProvider` error | 🔴 Blocking | Fix auth config |
| `Unhandled` in console | 🔴 Blocking | Fix unhandled rejection |
| `TypeError` in console | 🟡 Warning | Investigate and document |

### Evidence Integrity

- [ ] PR URL is valid (not `/pull/new`)
- [ ] Commit SHA matches current HEAD
- [ ] Changed file/line mapping matches diff
- [ ] Claims do NOT contradict screenshots/logs

---

## Tooling Requirement

For frontend verification, agents should use:

1. **Playwright (local)** - For visual regression tests
   ```bash
   VISUAL_BASE_URL=http://localhost:5173 pnpm --filter frontend test:visual
   ```

2. **CI Workflows (automatic)** - Triggered on PR:
   - `visual-quality.yml` - Stylelint + Visual Regression
   - `lighthouse.yml` - Performance budgets

---

## Required PR Body Section

When frontend files are changed, include this section:

```markdown
## Frontend Evidence

### Route Matrix
| Route | Desktop | Mobile | Status |
|-------|---------|--------|--------|
| / | ✅ | ✅ | Pass |
| /sign-in | ✅ | ✅ | Pass |

### Runtime Health
- Console errors: 0
- Page errors: 0
- Unexpected Application Error: No

### Evidence
- Commit SHA: [commit hash]
- Visual tests: 10 passed
- CI workflow: [link to workflow run]

### Baseline Updates
- [ ] No baseline changes needed
- [ ] Baselines updated with justification: [reason]
```

---

## Pass/Fail Criteria

### ✅ Pass (PR Ready)
- All visual tests pass (or baselines intentionally updated)
- CI checks green (Stylelint, Visual Regression, Lighthouse)
- Evidence section included in PR body
- Zero blocking errors

### ❌ Fail (PR Blocked)
- Visual tests fail without baseline update justification
- Blocking error pattern detected
- Missing Frontend Evidence section
- Evidence contradicts claims

---

## Artifact Paths

```
frontend/e2e/visual/__snapshots__/     # Visual baselines
frontend/playwright-report/             # HTML report (on failure)
frontend/.lighthouseci/                 # Lighthouse results
```

---

## CI Workflows

| Workflow | Trigger | Checks |
|----------|---------|--------|
| `visual-quality.yml` | PR to frontend files | Stylelint, Visual Regression |
| `lighthouse.yml` | PR to frontend files | Performance budgets (LCP, CLS, a11y) |

---

## Common Issues

### "Snapshot doesn't exist"
- Run with `--update-snapshots` flag or `test:visual:update`
- Commit new baselines with justification

### "Port 5173 already in use"
- Kill existing preview server: `pkill -f "vite preview"`
- Or use `VISUAL_BASE_URL` to skip webServer startup

### "Module format error" (lighthouserc)
- Config is `lighthouserc.cjs` (CommonJS, not ESM)
- Use `--config lighthouserc.cjs` if running manually

---

## Quick Reference Commands

```bash
# Build
pnpm --filter frontend build

# Type check
pnpm --filter frontend type-check

# Stylelint
pnpm --filter frontend lint:css

# Visual tests (with preview server running)
VISUAL_BASE_URL=http://localhost:5173 pnpm --filter frontend test:visual

# Update baselines
VISUAL_BASE_URL=http://localhost:5173 pnpm --filter frontend test:visual:update

# Preview server
pnpm --filter frontend preview --port 5173
```
