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

## Exceptions

- `subbrowser` remains an antigravity-specific exception
- browser MCP surfaces such as `chrome-devtools` are optional specialist/debug tools, not the standard manual verification path

## Practical Rule

If the task is:

- "click around, inspect, verify, screenshot, repro" -> use `agent-browser`
- "assert behavior, codify the flow, run in CI" -> use `Playwright`
