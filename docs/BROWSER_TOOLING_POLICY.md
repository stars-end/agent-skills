# Browser Tooling Policy

This repo uses a clear split between manual browser verification and automated browser testing.

## Primary Manual Browser Tool

For CLI agents, the primary manual browser tool is `agent-browser`.

Use it for:

- exploratory verification
- UI walkthroughs
- screenshots and manual evidence capture
- form interactions
- auth-cookie-driven QA flows
- checking console/errors during an interactive session

## Automated Browser Testing

Use `Playwright` for:

- CI/E2E
- assertion-heavy checks
- reproducible test cases
- regression coverage

Do not treat `agent-browser` as a replacement for Playwright test coverage.

For Prime Radiant guarded-route QA, `Playwright` is a narrow debugging exception only when you need interception or a reproducible assertion trace that `agent-browser` cannot provide.

## Prime Radiant QA Lanes

- `/demo` is the no-auth lane for guest/demo validation.
- `/v2` and `/brokerage` are bypass-default lanes for routine product verification.
- real-auth is exception-only and should be used only when testing auth-specific behavior.
- For manual QA on guarded routes, use the canonical Prime Radiant helper from PR #974: `make qa-bypass-cookie` or `make qa-bypass-cookie FORMAT=verify BACKEND_URL=...`.

## Exceptions

- `subbrowser` remains an antigravity-specific exception
- browser MCP surfaces such as `chrome-devtools` are optional specialist/debug tools, not the standard manual verification path

## Practical Rule

If the task is:

- "click around, inspect, verify, screenshot, repro" -> use `agent-browser`
- "assert behavior, codify the flow, run in CI" -> use `Playwright`
