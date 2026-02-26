# Frontend Evidence Contract

> **Purpose:** Prevent false-positive UI/UX handoffs by enforcing standard evidence requirements for frontend PRs.
> **Version:** 1.0 (bd-4n6s)

## Route Matrix (Required)

Test each route in both authentication modes:

### Mode 1: No-Cookie (Unauthenticated)

| Route | Expected Behavior | Screenshot | Console Errors |
|-------|-------------------|------------|----------------|
| `/` | Landing page renders | ✅/❌ | 0 errors |
| `/sign-in` | Sign-in form renders | ✅/❌ | 0 errors |
| `/sign-up` | Sign-up form renders | ✅/❌ | 0 errors |
| `/demo` | Demo workspace loads | ✅/❌ | 0 errors |

### Mode 2: Bypass-Cookie (Authenticated Stub)

| Route | Expected Behavior | Screenshot | Console Errors |
|-------|-------------------|------------|----------------|
| `/v2` | V2 workspace renders | ✅/❌ | 0 errors |
| `/brokerage` | Brokerage connections | ✅/❌ | 0 errors |

## Runtime Health Checks (Required)

### Error Pattern Detection

The following patterns must NOT appear in console or page:

| Pattern | Level | Action |
|---------|-------|--------|
| `Unexpected Application Error` | 🔴 Blocking | PR cannot proceed |
| `ClerkProvider` error | 🔴 Blocking | Fix auth config |
| `Unhandled` in console | 🔴 Blocking | Fix unhandled rejection |
| `TypeError` in console | 🟡 Warning | Investigate and document |
| `clerk` error (non-blocking) | 🟡 Warning | May be expected in demo mode |

### Evidence Integrity

- [ ] PR URL is valid (not `/pull/new`)
- [ ] Commit SHA matches current HEAD
- [ ] Changed file/line mapping matches diff
- [ ] Claims do NOT contradict screenshots/logs

## Tooling Requirement

For frontend verification, use BOTH:

1. **Playwright MCP** - For automated navigation, screenshots, and accessibility checks
2. **Chrome DevTools MCP** - For performance traces, console capture, and layout analysis

## Required PR Body Fields

When frontend files are changed, include:

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

### Evidence Files
- Screenshots: [link to artifacts]
- PR URL: https://github.com/org/repo/pull/XXX
- Commit SHA: abc1234

### Tooling Used
- [x] Playwright MCP
- [x] Chrome DevTools MCP
```

## Pass/Fail Criteria

### ✅ Pass (PR Ready)

- All routes in matrix pass
- Zero blocking errors
- Evidence integrity verified
- Both tooling used

### ❌ Fail (PR Blocked)

- Any route fails to render
- Blocking error pattern detected
- Evidence contradicts claims
- Missing required evidence

## Artifact Paths

Store evidence artifacts at:

```
frontend/e2e/visual/__snapshots__/
frontend/playwright-report/
.lighthouseci/
```

## Quick Reference

```bash
# Run visual regression
pnpm --filter frontend test:visual

# Run Playwright route check
pnpm --filter frontend test:e2e -- --grep "route"

# Capture screenshots manually
pnpm --filter frontend test:visual:update
```
