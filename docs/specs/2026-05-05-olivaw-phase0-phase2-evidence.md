# Olivaw Phase 0-2 Evidence

Feature-Key: `bd-1ocyi`

Date: 2026-05-05

Scope: Phase 0 runtime foundation, Phase 1 Slack gateway, and Phase 2 Google
Workspace/gog readiness for Olivaw.

## Summary

Olivaw is ready to proceed into Phase 3 adapter work.

Verified:

- Hermes/Olivaw runs on `macmini` under a user LaunchAgent.
- Slack Socket Mode connects and the `groups:read` residual warning is cleared.
- Olivaw is present in the required Slack channels and responds in DM and
  `#coding-misc`.
- `gog` is authenticated for `fengning@stars-end.ai` with Gmail, Calendar,
  Drive, Docs, Sheets, and Contacts scopes.
- `gog auth doctor --check` passes with one readable OAuth token and successful
  refresh.
- Gmail, Calendar, Drive, and Contacts read smoke tests work with JSON output.

Caveats:

- The Google Cloud project created during setup is provisionally named
  `My Project 8079` with project ID `steady-burner-495415-t1`, under the
  visible organization `firstlaw.finance`. It is functional for Olivaw, but
  should be renamed or replaced if Star's End wants a cleaner long-term Cloud
  project home.
- The OAuth client briefly had two client secrets in the Google UI. The active
  downloaded client secret was stored into `gog`; the downloaded copy was
  removed from `~/Downloads`. The older unused secret should be disabled or
  deleted in Google Cloud after human confirmation.
- One `#coding-misc` Slack smoke test caused both Olivaw and Clawdbot to echo
  the requested sentinel. This is useful evidence that channel-level agent
  ambiguity still needs a later routing/noise rule.

## Phase 0 Runtime Foundation

Beads and auth preflight:

- `bdx dolt test --json`: passed.
- `bdx preflight --json`: passed.
- `~/agent-skills/scripts/dx-bootstrap-auth.sh --json`: passed with
  `mode=agent_ready_cache`.
- `~/agent-skills/scripts/dx-load-railway-auth.sh -- railway whoami`: passed
  for `fengning@stars-end.ai`.

Hermes runtime:

- Hermes binary: `/Users/fengning/.local/bin/hermes`.
- Version: Hermes Agent `v0.12.0 (2026.4.30)`.
- `hermes doctor`: core runtime passed; nonblocking warnings remain for unused
  providers and optional submodule/tool checks.
- `hermes profile list`: `olivaw` is running with model
  `deepseek-v4-flash`.
- `hermes gateway status`: `olivaw` gateway running.

LaunchAgent:

- Plist:
  `/Users/fengning/Library/LaunchAgents/ai.hermes.gateway-olivaw.plist`
- Command:
  `python -m hermes_cli.main --profile olivaw gateway run --replace`
- `HERMES_HOME`:
  `/Users/fengning/.hermes/profiles/olivaw`
- Logs:
  `/Users/fengning/.hermes/profiles/olivaw/logs/gateway.log`
  and
  `/Users/fengning/.hermes/profiles/olivaw/logs/gateway.error.log`
- Restart evidence: gateway restarted after Slack scope refresh and came back
  with a fresh process.

Locality:

- No public Hermes dashboard/API bind was found in local listener checks.

Secret checks:

- OP cache resolution succeeded for Olivaw Slack bot token, Olivaw Slack app
  token, and DeepSeek API key names.
- No secret values were printed into this evidence file.

## Phase 1 Slack Gateway

Slack API/runtime:

- Slack `auth.test`: passed for team `Star's End` and user `olivaw`.
- Required channel membership verified:
  - `#all-stars-end`
  - `#lifeops`
  - `#fleet-events`
  - `#coding-misc`
  - `#finance`
  - `#railway-dev-alerts`
- Slack OAuth reinstall completed after confirming `groups:read` was present in
  the app scope configuration but not reflected in the stored token.
- After reinstall, `users.conversations?types=private_channel` succeeded.
- Gateway restart after reinstall logged:
  - authenticated as `@olivaw`
  - Socket Mode connected
  - channel directory built with 19 targets
- No fresh missing-`groups:read` warning appeared after restart.

Manual Slack checks:

- Slack Mac app / Computer Use: `/hermes sethome` succeeded in
  `#all-stars-end`.
- DM smoke: Olivaw replied with the sentinel `DM_OK_20260505`.
- `#coding-misc` app mention: Olivaw replied with the sentinel
  `CODING_OK_20260505` in thread.
- `#coding-misc` caveat: Clawdbot also echoed `CODING_OK_20260505`, so later
  channel-routing work should prevent accidental multi-agent echo behavior.

Channel policy carried forward:

- `#railway-dev-alerts` and `#fleet-events` remain alert-input channels where
  Hermes should reply in-thread and avoid routine all-clear top-level posts.
- `#lifeops`, `#finance`, `#coding-misc`, and `#all-stars-end` remain
  discussion/digest channels.

## Phase 2 Google Workspace / gog

Installed tools:

- `gcloud`: `/opt/homebrew/bin/gcloud`.
- Current `gcloud` CLI auth/project was personal (`fengning9c@gmail.com`,
  `clawdbot9c`) and was not used as business setup truth.
- `gog`: `/opt/homebrew/bin/gog`.
- `gog --version`: `v0.15.0 (e0338d5 2026-05-05T05:50:19Z)`.
- Actual command surface for client credentials:
  `gog auth credentials set <credentials>`.

Google Cloud setup:

- Browser account used: `fengning@stars-end.ai`.
- Google Cloud project: `steady-burner-495415-t1`
  (`My Project 8079`).
- OAuth consent:
  - app name: `Olivaw gog workspace`
  - support/contact: `fengning@stars-end.ai`
  - audience: `Internal`
- Enabled APIs:
  - Gmail API
  - Google Calendar API
  - Google Drive API
  - Google Docs API
  - Google Sheets API
  - Google People API
- OAuth client:
  - type: Desktop
  - name: `Olivaw gog desktop`
- Credential storage:
  `gog auth credentials set <downloaded-client-json> --client olivaw-gog
  --json --no-input`
- Stored credential path:
  `/Users/fengning/Library/Application Support/gogcli/credentials-olivaw-gog.json`
- Temporary downloaded client-secret JSON was removed from `~/Downloads` after
  successful import.

OAuth result:

- `gog auth add fengning@stars-end.ai --services gmail,calendar,drive,docs,sheets,contacts`
  completed through browser OAuth.
- Browser success page confirmed gog was authorized for Google Workspace.
- Token stored for client `olivaw-gog` and account `fengning@stars-end.ai`.
- Authorized services:
  - `calendar`
  - `contacts`
  - `docs`
  - `drive`
  - `gmail`
  - `sheets`
- Safety flag used for agent-facing checks:
  `--gmail-no-send`.

Doctor:

Command:

```bash
GOG_ACCOUNT=fengning@stars-end.ai \
  gog --client olivaw-gog --gmail-no-send auth doctor --check --json
```

Result:

- status: `ok`
- config path: ok
- keyring backend: ok
- keyring open: ok
- tokens: `1 readable OAuth token of 1 stored token account`
- refresh exchange: succeeded for the Olivaw business account token

Read smoke tests:

```bash
GOG_ACCOUNT=fengning@stars-end.ai \
  gog --client olivaw-gog --gmail-no-send calendar calendars --json --no-input
```

- Passed.
- Returned 2 calendars, including the primary
  `fengning@stars-end.ai` calendar.

```bash
GOG_ACCOUNT=fengning@stars-end.ai \
  gog --client olivaw-gog --gmail-no-send drive ls --json --no-input
```

- Passed.
- Returned Drive file metadata.

```bash
GOG_ACCOUNT=fengning@stars-end.ai \
  gog --client olivaw-gog --gmail-no-send contacts list --json --no-input
```

- Passed.
- Returned zero contacts, which is a valid empty account result.

```bash
GOG_ACCOUNT=fengning@stars-end.ai \
  gog --client olivaw-gog --gmail-no-send gmail search 'newer_than:7d' \
  --max 3 --json --no-input
```

- Passed.
- Returned 3 Gmail threads.

Not yet completed in Phase 2:

- The Hermes-facing Google wrapper/skill has not yet been implemented.
- Explicit blocked-action tests for Gmail send/delete and Drive sharing/admin
  are still Phase 2/6 work before any live sensitive finance or health pilot.

## Manual Tooling Friction Log

Computer Use:

- Worked well for Slack Mac app operations, `/hermes sethome`, and browser OAuth
  screens where account selection matters.
- Better fit for the many-Google-account reality because it lets the operator
  visually confirm the signed-in account before taking an action.
- Main friction: app targeting can be finicky; `com.google.Chrome` was more
  reliable than the display name `Google Chrome`.

Chrome DevTools MCP:

- Live exposure check succeeded: `list_pages` could see the active Chrome pages.
- Important friction: page listing exposed the OAuth callback URL, including
  sensitive query parameters. Do not use DevTools MCP page listings as routine
  evidence on auth callback pages.
- Best fit is post-auth inspection, console/network debugging, and local app
  testing when URL exposure is safe.

Operational rule:

- Use Computer Use first for Slack UI, OAuth setup, account switching, and any
  workflow involving sensitive callback URLs.
- Use Chrome DevTools MCP for browser debugging after auth is complete or on
  non-sensitive local/test pages.
- Use `agent-browser` or Playwright when a repeatable CLI/E2E check is more
  valuable than manual UI confirmation.

## Current Readiness

Ready now:

- Phase 3 deterministic Slack/cron adapter implementation can begin.
- Phase 4 Kanban boundary investigation can begin.
- Phase 5 coding dispatch design can begin, but implementation should wait for
  the dx-loop/dx-runner command contract and Feature-Key hard-failure mechanism.

Hold before live finance/health workflows:

- Implement blocked-action tests.
- Confirm retention/logging redaction behavior.
- Ensure healthcare/finance payloads route to approved Docs/Sheets/Drive
  artifacts, not raw Slack or default Hermes memory/logs.
