# Hermes Maximal Integration Program

Feature-Key: `bd-k9rfq`

## Summary

This is an `ALL_IN_NOW` platform program, not a narrow Slack bot setup.

Hermes should become a first-class operational layer across:

- startup operations
- coding orchestration
- Google Workspace
- Slack
- browser-based admin tasks
- webhook-driven follow-up
- cross-session memory
- future Gas City orchestration surfaces

The implementation will still be phased, but the scope is intentionally broad
and comprehensive now so that we do not keep rediscovering the same boundaries
and bolt-on requirements later.

Hard boundaries remain:

- Hermes becomes the reasoning, workflow, and operator layer.
- Agent Coordination remains the deterministic transport/control plane.
- Codex Desktop remains the primary interactive coding surface.
- OpenCode remains a secondary coding execution lane.
- Gas City becomes the orchestration pane rather than an ad hoc bot pile.
- Google Workspace access starts with the Star's End business account
  `fengning@stars-end.ai`, not personal Google accounts.

The intent is maximal useful integration without pretending that Hermes
profiles, Slack bots, or memory plugins are security boundaries when they are
not.

## Problem

The current stack has strong primitives, but they are fragmented:

- deterministic Slack/control-plane logic already exists in Agent Coordination
- coding happens mostly in Codex Desktop, partly in OpenCode, across local and
  remote canonical VMs
- startup and personal operations live across Slack, GitHub, Railway, Google,
  finance/admin workflows, and ad hoc Codex sessions
- Gas City is emerging as the code-factory/orchestration pane, but not yet the
  unified operator surface

Without an explicit contract, "use Hermes everywhere" would likely create:

- duplicated Slack/control-plane logic
- excessive data access without clear trust boundaries
- confused ownership between Codex/OpenCode/Gas City/Hermes
- brittle automations that mix deterministic routing with LLM reasoning

## Goals

1. Make Hermes a first-class operational assistant for startup, coding,
   logistics, healthcare-admin, and finance-adjacent workflows.
2. Integrate Hermes with Slack, Google Workspace, browser automation, coding
   workflows, and future Gas City orchestration.
3. Preserve deterministic ownership where deterministic systems are already the
   right tool.
4. Enable remote coding task launch, follow-up, and session-aware handoff from
   Slack where feasible.
5. Build a durable profile, memory, hook, and routing architecture so Hermes
   can grow without becoming a sprawl of one-off flows.
6. Bound data access by profile, account, and workflow rather than by vague
   "trust me" assumptions.

## Non-Goals

1. Replace Agent Coordination as the canonical deterministic control plane.
2. Replace Codex Desktop as the main coding surface.
3. Treat Hermes profiles as a sandbox or hard security boundary.
4. Migrate Prime Persona Tester off local Codex Desktop automation in this
   program.
5. Attach personal Gmail or broad personal Google Workspace data on day one.
6. Adopt a new memory provider before the built-in memory + Beads split is
   proven insufficient.

## ALL_IN_NOW Decision

`ALL_IN_NOW` means:

- adopt Hermes as a core, not experimental, workflow surface
- connect it to the Star's End business Google Workspace
- create the dedicated `finance`, `family`, and `coder` profiles now
- design explicit coexistence with Agent Coordination and Gas City now
- treat Slack, hooks, webhooks, browser automation, goals, background tasks,
  provider routing, and profile design as first-class parts of the program
- prioritize Slack-driven remote coding task launch and follow-up now
- design the coding and operations surface as a multi-surface system:
  Hermes + Codex Desktop + OpenCode + Gas City + Agent Coordination

It does **not** mean:

- granting unnecessary personal data access
- collapsing deterministic controllers into an LLM bot
- faking native Codex Desktop integration that does not exist
- turning every Hermes feature on blindly without a contract for ownership,
  data access, and delivery

## Hermes feature-scope map

This program should explicitly account for the major Hermes feature families,
not just Slack messaging and profiles.

### Core

- tools and toolsets
- skills system
- persistent memory
- context files
- context references
- checkpoints and rollback

### Automation

- scheduled tasks (cron)
- background tasks and isolated sessions
- persistent goals
- subagent delegation
- execute-code workflows
- event hooks
- kanban / multi-agent board
- batch processing where it creates real value

### Media and web

- browser automation
- vision / image handling
- optional voice and TTS later, if there is a concrete workflow payoff

### Integrations

- Google Workspace
- MCP integration
- ACP editor integration
- API server
- provider routing
- fallback providers
- credential pools
- external memory providers

### Customization and extension

- SOUL/personality
- plugins
- custom skills
- hook packages

## Program-level architecture

The right mental model is:

- Hermes is the operator
- Agent Coordination is the deterministic nervous system
- Codex Desktop is the primary craft surface for coding
- OpenCode is the headless and secondary craft surface
- Gas City is the orchestration pane and systems substrate

We should design toward that shape now, even if the implementation arrives in
phases.

### Deployment topology contract

Hermes needs an explicit runtime anchor. The program should not proceed with an
abstract "gateway install strategy" only.

Initial topology:

- `macmini`
  - primary Hermes operator host
  - Slack gateway host
  - local browser-automation host
  - local Codex Desktop adjacency host
- `epyc12`
  - primary remote coding execution host
  - Beads central Dolt server host
  - primary high-throughput automation and coding-side execution host
- `epyc6` and `homedesktop-wsl`
  - secondary remote execution targets
  - overflow/specialized coding targets

Process supervision must be explicit:

- Hermes gateway and long-lived services must run under a declared supervisor
  surface
- macOS-hosted long-lived Hermes services should use LaunchAgent or an
  equivalent explicit host contract
- Linux-hosted long-lived Hermes services should use systemd user services or
  an equivalent explicit host contract

This is not optional documentation. It is part of the execution substrate.

### Canonical VM capability matrix

| Host | Primary Hermes role | Coding role | Browser role | Default profile access |
| --- | --- | --- | --- | --- |
| `macmini` | primary operator host, Slack gateway, local Hermes services | local Codex Desktop adjacency and local-only automations | primary Chrome / DevTools MCP / `agent-browser` host | `olivaw`, `family`, `finance`, `coder` |
| `epyc12` | remote execution target and Beads-adjacent automation host | primary remote coding throughput; default governed `dx-loop` / `dx-runner` host | none by default | `coder`, selected `olivaw` automation |
| `epyc6` | secondary remote execution target | overflow or specialized coding work | none by default | `coder` only unless explicitly expanded |
| `homedesktop-wsl` | secondary remote execution target | WSL-specific or overflow coding work | none by default | `coder` only unless explicitly expanded |

Default routing rule:

- browser-heavy and desktop-local workflows start on `macmini`
- governed coding tasks start on `epyc12` unless the task needs local macOS
  state or a specific alternate host
- finance/family profiles should not target remote coding hosts unless an
  explicit workflow requires it

## Active Contract

### 1. Role split

#### Agent Coordination

Owns:

- deterministic Slack posting/routing
- alert transport
- heartbeats
- queue hygiene
- controller duties
- policy-driven dispatch/control logic

#### Hermes

Owns:

- reasoning over multi-system context
- profile-scoped startup/personal workflows
- Google Workspace interactions
- Slack conversation interface
- cron jobs that synthesize, triage, draft, summarize, or follow through
- hook-driven reactions and webhook-triggered workflows

#### Codex Desktop

Owns:

- primary interactive coding work
- local app-native session handling
- desktop-local automations already intentionally placed there

#### OpenCode

Owns:

- secondary coding lane
- headless/server-based coding tasks
- resumable session execution where its session model fits better than Codex

#### Gas City

Owns the eventual pane of glass for:

- orchestration state
- agent/session visibility
- coding dispatch visibility
- routing/launch surfaces

Gas City should not become "Hermes in Go." It should surface and route across
systems.

### 2. Trust and data boundary model

- Startup/business Google Workspace access is allowed through
  `fengning@stars-end.ai`.
- Personal Google account access is out of scope for the first cut.
- The Star's End business calendar may be shared into the founder's personal
  Google Calendar for unified planning visibility. Business Gmail should remain
  a separate mailbox boundary; Hermes may summarize or draft from business Gmail
  without blending raw mailboxes into the personal account.
- Finance/health/family workflows are profile-scoped and should start with
  least-privilege inputs.
- Sensitive finance/health workflows should begin with Docs/Sheets/Drive and
  filtered inputs before broad inbox access.
- Hermes profiles separate state, memory, sessions, cron jobs, and tokens, but
  they do not sandbox filesystem access.

### 2.5 Secret-access model

Per-profile secret access must be explicit.

- `olivaw`
  - may use startup/business secret material needed for Slack, Google
    Workspace, webhook ingestion, and approved startup systems
- `coder`
  - may use coding and deployment secrets needed for approved coding workflows
    and governed remote execution
- `family`
  - should default to minimal or no secret-backed system access beyond approved
    messaging/calendar/browser tasks
- `finance`
  - should begin with no direct financial-secret authority unless a later task
    explicitly approves it

Secret handling contract:

- OP CLI remains the canonical secret source
- profile-specific access must be allowlisted, not inferred
- Hermes-launched tasks should prefer injected least-privilege runtime context
  or approved helper wrappers over ad hoc secret fetches
- any task that cannot meet the Agent Secret-Auth Invariant must fail closed

Technical data-security contract:

- sensitive finance/healthcare source documents must land in approved
  Workspace artifacts or bounded exports, not Hermes session memory by default
- Slack notifications for finance/healthcare workflows should contain only
  summaries and links to approved artifacts, not raw source payloads
- every finance/healthcare workflow must define retention expectations for
  intermediate files, screenshots, browser downloads, and generated artifacts
- workflow logs must avoid raw account numbers, member IDs, claim numbers, or
  full document payloads unless a later task explicitly approves a redaction
  and storage plan
- approved artifacts should preserve enough audit trail to reconstruct what was
  read, produced, and sent without relying on chat logs

### 3. Automation boundary

- Deterministic checks stay deterministic.
- Hermes may consume deterministic outputs and generate summaries, next actions,
  or routed follow-ups.
- Hermes should not become the canonical owner of fleet checks, parity checks,
  queue enforcers, or controller heartbeats.

### 3.5 Deterministic input contract

For every `dx-*` or deterministic producer that Hermes consumes, the input
surface must be declared:

- stdout/text artifact
- file artifact
- Beads artifact
- Slack message/thread
- webhook/event

Hermes should consume deterministic outputs through explicit adapters, not by
implicitly scraping whichever human-facing surface happens to exist.

Initial producer mapping:

| Producer | Initial Hermes adapter surface | Hermes role |
| --- | --- | --- |
| `dx-founder-daily.sh` | stdout/text artifact plus existing Slack-thread delimiter semantics | summarize, route, and follow up on founder-briefing outputs |
| `dx-fleet-check.sh` and canonical VM status emitters | `#fleet-events` Slack messages plus stdout/text or file artifacts emitted by deterministic fleet checks | summarize fleet health and suggest follow-up, without owning fleet enforcement |
| `queue-hygiene-enforcer.sh` | file or Beads-linked artifact from deterministic queue policy | explain queue-health outcomes and route human follow-up |
| `railway-parity-check.sh` | stdout/file artifact from deterministic parity check | summarize Railway drift and draft remediation tasks |
| `dx-eodhd-monitor.sh` | existing `#railway-dev-alerts` Slack summaries plus deterministic monitor output where available | summarize market-data/pipeline anomalies and route follow-up |
| Affordabot nightly dispatch | GitHub Actions artifact, Beads/task artifact, or deterministic summary output | summarize dispatch outcomes and capture follow-up work |

These mappings are starting contracts. Phase 1 should verify the actual runtime
surface of each producer before wiring Hermes automation.

### 4. Session and execution boundary

- Hermes may launch, summarize, and coordinate coding sessions.
- Codex Desktop remains the best local interactive UI for coding sessions.
- OpenCode remains the best first headless coding lane.
- Gas City should eventually surface session inventory, routing, and control.
- Session continuity should be designed around durable identifiers and surfaced
  artifacts, not around pretending every tool shares the same resume primitive.

### 4.5 Beads read/write contract

Beads is not just "memory in principle." Hermes needs a concrete contract for
reading and, where approved, writing Beads state.

Read-path examples:

- query active work context
- attach startup/coding summaries to task history
- retrieve targeted memory records for cross-session context

Write-path examples:

- create follow-up tasks only through approved surfaces
- add task-local comments when a workflow is explicitly task-bound
- preserve durable cross-agent memory in Beads memory primitives rather than in
  ad hoc profile notes

The central runtime truth remains the Dolt-backed Beads server on `epyc12`.

### 4.6 Sensitive-data "must never" guardrails

The following rules should be explicit in Phase 0/1:

- Hermes must never auto-submit healthcare claims without an explicit later
  approval task
- Hermes must never initiate Mercury banking actions or money movement
- Hermes must never treat Slack as the canonical sink for healthcare-sensitive
  payloads
- Hermes must never assume built-in memory or chat/session logs are an
  acceptable default store for healthcare or finance source documents
- finance and healthcare artifacts should default to approved Docs/Sheets/Drive
  sinks or bounded exports, not broad chat distribution

Enforcement tests should exist before live finance/healthcare data access:

- blocked-action tests for claim submission and Mercury money movement
- redaction tests for Slack notifications
- memory/log tests proving raw sensitive payloads are not stored by default
- artifact-routing tests proving Docs/Sheets/Drive are used for source material
  and audit trails

## Current-State Findings

### Existing deterministic stack

The current repos already contain recurring deterministic jobs that should stay
outside Hermes core ownership:

- `dx-founder-daily.sh`
- `dx-fleet-check.sh`
- `queue-hygiene-enforcer.sh`
- `railway-parity-check.sh`
- `dx-eodhd-monitor.sh`
- Affordabot nightly dispatch workflows

These are strong Hermes inputs, but weak Hermes replacement candidates.

### Shared-substrate disposition still needed

Two existing shared surfaces need explicit disposition decisions:

- `llm-common`
  - decision: reusable provider/client abstractions that are broadly useful
    across product repos should continue to live in `llm-common`
  - current direction: `llm-common` is undergoing significant migration toward
    LiteLLM plus Pydantic AI, with DeepSeek V4 as the new default path
  - Hermes-specific routing, profile policy, and operator-facing workflow logic
    should remain Hermes-side and must not fork shared provider code without a
    clear reason
- EODHD pipeline and monitoring work
  - decision: Hermes consumes explicit outputs from deterministic EODHD
    monitoring and ETL jobs, summarizes them, and routes follow-up actions, but
    does not own the pipeline runtime or alert-production logic
  - current source: EODHD summaries already post to Slack in
    `#railway-dev-alerts`; Hermes should consume that existing surface before
    inventing another alert lane
- Fleet and canonical VM status work
  - current source: `#fleet-events` is the canonical Slack lane for
    `dx-*` workflow and canonical VM status updates; Hermes should consume and
    summarize that lane without becoming the fleet-status producer

### Existing Codex-local decision already made

Prime Persona Tester was explicitly placed in local Codex Desktop automation.
That decision stands unless a future task intentionally revisits it.

### Hermes Slack surface already present

Olivaw's Slack manifest already exposes a large command surface, including:

- `/background`
- `/queue`
- `/goal`
- `/resume`
- `/agents`
- `/sethome`
- `/reload-mcp`
- `/kanban`

This makes Hermes immediately useful as an operational Slack surface without
inventing a new command UX.

### Hermes feature capabilities relevant to this program

Hermes already has platform features that materially matter for this plan:

- cron jobs can attach skills, run in fresh sessions, target a specific
  `workdir`, and deliver results to Slack, local files, or other configured
  targets
- background messaging tasks run in isolated sessions and do not block the main
  chat
- sessions are durable across Slack and CLI usage, backed by both SQLite
  metadata and JSONL transcripts
- profiles are true state splits with separate config, sessions, skills, cron
  jobs, and gateway state, but not a filesystem sandbox
- hooks can run both as gateway-only hooks and cross-surface plugin/shell hooks
- API server and ACP both expose Hermes beyond the plain CLI
- provider routing, fallback providers, and credential pools can make Hermes
  materially more reliable once usage grows

### Gas City fit is real, not hypothetical

Gas City already has the right shape for this program:

- multi-provider runtime abstraction
- ACP-capable runtime support
- session and orchestration primitives
- existing awareness of Codex and OpenCode as agent/runtime classes
- a strong "pane and controller" architecture that can surface external systems
  without swallowing their logic

### Coding CLI affordances already present

Current local CLIs support the needed launch/resume primitives:

- `codex exec`
- `codex exec resume`
- `codex resume`
- `opencode run`
- `opencode serve`
- `opencode attach`
- `opencode session list`

That means Slack-launched coding tasks are feasible through Hermes terminal/SSH
or future Gas City adapters, even if "resume directly in the Codex Desktop UI"
is not yet a first-class Hermes primitive.

## Architecture / Design

## Profile model

### Default `olivaw` profile

Purpose:

- startup operations
- Slack gateway
- Google Workspace business integration
- hooks/webhooks
- cross-system summaries
- background tasks
- goals
- startup-facing browser workflows

Primary connected assets:

- Slack (`Olivaw`)
- Google Workspace for `fengning@stars-end.ai`
- GitHub/Railway-facing automations
- startup docs, calendars, and email

### `coder` profile

Purpose:

- coding-adjacent orchestration
- remote task launch
- code review, run summaries, session bookkeeping
- Codex/OpenCode/Gas City integration experiments
- MCP-heavy tool use
- coding goals / kanban usage
- coding-specific skills and hooks

Likely integrations:

- Slack
- GitHub
- selected MCP servers
- optional coding-focused memory later
- API-server or ACP experiments if they create real leverage

### `family` profile

Purpose:

- scheduling
- reservations
- household logistics
- selected healthcare admin workflows
- browser automation for admin tasks
- calendar-first family planning

Allowed access should begin with:

- shared calendar(s)
- bounded Drive folders
- optionally filtered email

### `finance` profile

Purpose:

- startup-adjacent admin
- household finance tracking
- tax-adjacent organization
- reimbursements / expense triage / document handling
- healthcare expense organization
- claims / EOB / bill triage support

Allowed access should begin with:

- Sheets
- Docs
- Drive
- manual exports / forwarded messages

Broad email access is a later decision, not the default.

## Feature families and their role in this program

### 1. Messaging, sessions, and background work

Hermes messaging is not just "chat in Slack."

Program scope should include:

- normal Slack interaction
- background tasks from Slack
- session resume/search patterns
- home-channel strategy by profile
- thread discipline for long-running work
- delivery rules for cron, hooks, and webhooks

This matters because coding dispatch, startup operations, and healthcare/admin
work all benefit from asynchronous follow-through instead of synchronous chat.

### 2. Goals and iterative autonomy

Persistent goals belong in scope for both coding and operations.

Best fits:

- coding investigations that should keep going without repeated "continue"
- startup ops loops with bounded turn budgets
- long-form research or reconciliation work

Do not use goals as a replacement for deterministic controllers.

### 3. Cron and recurring operations

Cron belongs in scope as a primary automation surface, not a side feature.

Program scope should include:

- startup daily/weekly briefings
- coding status digests
- family calendar preparation
- finance/admin reminders and reconciliations
- health/admin follow-up loops

Workdir-aware jobs are especially important for coding and repo-aware tasks.

### 4. Hooks, plugins, and webhook ingestion

Hooks and webhooks are core to making Hermes operationally serious.

Program scope should include:

- gateway hooks for logging and lifecycle events
- plugin/shell hooks for guardrails, context injection, and tool interception
- webhook routes for GitHub, Railway, Stripe-like operational sources, and
  other startup systems
- explicit prompt-injection and isolation rules for webhook-exposed surfaces

### 5. Google Workspace as the business operations backbone

Google Workspace is not just an add-on integration. It is one of the main
operating substrates for this program:

- Gmail
- Calendar
- Drive
- Docs
- Sheets
- Contacts

The business workspace `fengning@stars-end.ai` becomes the default workspace
surface for founder/startup operations.

### 6. Browser automation

Browser automation belongs in scope for concrete operator workflows:

- restaurant reservations
- healthcare portal navigation
- logistics/admin tasks
- founder research tasks that need live browser interaction
- websites where email/phone replacement is valuable

This should be treated as an intentional capability lane, not as a novelty.

### 7. Coding integration surfaces

This program should explicitly cover all of:

- Slack -> Hermes -> `codex exec`
- Slack -> Hermes -> `opencode run`
- Slack -> Hermes -> remote SSH on canonical VMs
- session/result artifact return to Slack
- Codex/OpenCode status summarization
- future session visibility in Gas City

### 8. ACP, API server, and MCP

These are separate surfaces and each deserves a role:

- ACP: editor-native Hermes in ACP-compatible editors
- API server: programmatic or frontend access to Hermes through an
  OpenAI-compatible endpoint
- MCP: access to external tool servers and internal APIs without custom native
  Hermes tools

This does not mean "replace Codex Desktop." It means Hermes can show up in more
places and expose more leverage.

Initial MCP inventory:

| MCP surface | In scope | Primary use |
| --- | --- | --- |
| Chrome DevTools MCP | yes | live-browser inspection and operator workflows |
| Serena | yes, for coding-adjacent review/edit planning | symbol-aware repository inspection when needed |
| GitHub MCP / GitHub CLI equivalent | likely | PR, issue, and repository context where Hermes workflows need it |
| Google Workspace skill / Google APIs | yes | Gmail, Calendar, Drive, Docs, Sheets, Contacts |
| Railway CLI/API/MCP equivalent | likely | deployment/status context through deterministic wrappers first |
| Beads via `bdx` / Dolt-backed runtime | yes | canonical work state and durable memory |

Phase 3 should turn this inventory into exact installed tools, auth surfaces,
and profile-specific allowlists.

### 9. Reliability controls

As Hermes becomes more central, the platform-reliability features should be in
scope:

- provider routing
- fallback providers
- credential pools
- model/task routing by job type

These are not day-one UX features, but they are program-level concerns now that
Hermes is being asked to become durable infrastructure.

### 10. Memory architecture

Memory needs an explicit contract:

- built-in Hermes memory for profile-specific continuity
- Beads remains canonical work memory for coding/program decisions
- external memory providers are optional follow-ons, not the immediate default
- the `coder` profile must not replace Beads with a vague memory plugin

### 11. Skills and local specialization

A serious Hermes deployment for this stack should expect custom skills.

Candidate custom-skill areas:

- startup weekly founder operating review
- healthcare bill triage
- reservation outreach
- coding dispatch wrappers for Codex/OpenCode/Gas City
- Slack-to-Google workflow helpers

### 12. Gas City as pane, not replacement

Gas City should eventually surface:

- Hermes profile inventory
- coding run inventory
- session status
- launchable actions
- orchestration history

It should not absorb Hermes' personality, memory, or workflow logic into Go.

## Google Workspace integration model

Use the Hermes Google Workspace skill against the Star's End business workspace:

- Gmail
- Calendar
- Drive
- Docs
- Sheets
- Contacts

Recommended first access pattern:

1. `olivaw`: full startup business workspace access appropriate for founder
   operations
2. `family`: selected shared calendars + folders
3. `finance`: Docs/Sheets/Drive first, Gmail later if needed

Do **not** start by giving all profiles broad mailbox access.

Personal/business account posture:

- share the Star's End business calendar into the founder's personal Google
  Calendar view when unified planning visibility is useful
- keep business Gmail separate from personal Gmail by default
- prefer Hermes-generated summaries, drafts, tasks, and calendar artifacts over
  personal-account mailbox blending

Additional scope:

- define startup folders, docs, and sheets that Hermes may treat as canonical
  working artifacts
- define whether Hermes may send business email directly or only draft first
- define calendar ownership for founder, team, and family-related schedules
- define which workflows produce Docs/Sheets outputs as first-class artifacts

## Slack + Agent Coordination coexistence

### Ownership rule

- Agent Coordination posts deterministic alerts and control-plane messages.
- Hermes posts interactive, contextual, reasoning-heavy outputs.

### Home channel rule

Hermes home channels should be set intentionally by profile/purpose:

- `olivaw`: startup operations home
- `coder`: coding operations home
- `family`: family/logistics home if needed
- `finance`: finance/admin home if needed

### Hook rule

Hermes hooks may:

- emit structured events
- ask Agent Coordination to deliver deterministic notifications
- trigger follow-up workflows

But they should not reimplement the deterministic transport contract already
owned by `dx-slack-alerts.sh` and the controller stack.

### Background and goal usage

Slack-side use should explicitly include:

- `/background` for non-blocking runs
- `/goal` for bounded iterative follow-through
- `/resume` for session continuation where Hermes owns the session
- thread-native status and artifact posting

## Coding integration model

## What is feasible now

### Slack -> Hermes -> coding task launch

Feasible now through Hermes terminal/SSH execution:

- launch `codex exec` jobs locally or on remote VMs
- launch `opencode run` locally or on remote VMs
- start/attach to `opencode serve`
- capture outputs, session IDs, and result artifacts

Governance rule:

- ad hoc raw CLI invocation is not sufficient as the steady-state contract
- coding tasks that materially matter should route through the canonical
  governance/orchestration surfaces where appropriate:
  - `dx-loop` for chained/non-trivial Beads work
  - `dx-runner` for governed provider execution
- direct `codex exec` or `opencode run` use should be framed as an explicitly
  approved or fallback execution primitive, not the only control-plane story

This should expand into an explicit command contract for:

- local Codex CLI execution
- remote Codex CLI execution on canonical VMs
- local OpenCode execution
- remote OpenCode execution
- worktree/workdir binding
- Feature-Key injection and commit-trailer enforcement
- artifact return into Slack threads
- governed run visibility through `dx-runner` or equivalent surfaced state

Worktree and Feature-Key contract:

- every Hermes-launched coding task must target a real worktree, not a
  canonical repo
- the default pattern is:
  - `dx-worktree create <BEADS_SUBTASK> <repo>`
  - run the coding surface inside that worktree
- every commit produced by a Hermes-launched coding task must include the
  required `Feature-Key: bd-...` trailer
- governed task wrappers should treat missing worktree binding or missing
  Feature-Key enforcement as a hard failure, not a warning

Enforcement mechanism:

- Hermes should not ask Codex/OpenCode to infer repository safety rules from
  prose only
- coding launch wrappers should materialize a prompt file that includes:
  - concrete `BEADS_SUBTASK`
  - concrete repo name
  - expected worktree command
  - required `Feature-Key` trailer
  - validation and return contract
- wrappers should run from the created worktree and export the Beads subtask in
  the runtime context where supported
- commit validation should rely on the existing repo hooks and the wrapper's
  done gate; a failed Feature-Key/pre-commit check is a failed Hermes-launched
  coding task

Governed dispatch interface:

- for chained work, Hermes should create or select a Beads subtask, write a
  prompt artifact, then call `dx-loop` against that subtask
- for direct governed provider execution, Hermes should call:
  - `dx-runner start --provider <provider> --beads <BEADS_SUBTASK>
    --prompt-file <prompt-file>`
- prompt artifacts should live in a declared runtime scratch/artifact directory
  and be referenced in Slack/Gas City results
- raw `codex exec` / `opencode run` should be used only for approved
  smoke/fallback paths or explicitly local workflows

### Slack -> Hermes -> remote VM orchestration

Feasible now through:

- SSH to canonical VMs
- controlled command templates
- existing repo/worktree wrappers
- future Gas City/dispatch adapters

Host capability matrix must be explicit:

- which hosts support local browser adjacency
- which hosts are preferred for coding throughput
- which hosts are acceptable for background jobs
- which profiles may target which hosts by default

### Codex/OpenCode bookkeeping from Hermes

Feasible now:

- list/record session IDs
- keep links/artifacts in Slack threads
- summarize status
- decide next action
- hand off between systems

### Hermes session model vs coding-session model

There are at least three different session layers in play:

1. Hermes chat/session history
2. Codex session history
3. OpenCode session/run history

The integration plan must keep those distinct and define the handoff artifacts
between them rather than pretending they are interchangeable.

## What is not yet first-class

### "Resume directly in Codex Desktop UI from Slack"

There is no currently-proven native Hermes -> Codex Desktop UI resume bridge.

The realistic first-cut contract is:

- Hermes launches or resumes the underlying Codex CLI/session where possible
- Hermes posts the resulting session/worktree details back to Slack
- the human opens/resumes in Codex Desktop when the app-native UI is the best
  next surface

This should be treated as a design target, not a shipped primitive.

## Gas City integration model

Gas City is the correct long-term place to unify:

- coding session inventory
- remote execution topology
- pooled/rigged agent visibility
- orchestration state across Hermes, Codex, and OpenCode

Recommended role:

- Gas City is the pane
- Hermes is the conversational operator
- Codex/OpenCode are execution engines
- Agent Coordination remains deterministic alert/control transport

That means the Gas City task is not "embed Hermes everywhere," but:

1. model Hermes-backed operations as surfaced actions
2. model Codex/OpenCode sessions as observable/launchable units
3. preserve controller/runtime truth in Gas City
4. preserve Gas City's zero-hardcoded-role and pane/controller architecture

## Automation candidates

## Best Hermes candidates

### Startup / founder

- founder daily brief synthesis over deterministic data
- GitHub/Railway issue triage and morning summary
- startup calendar + doc prep
- cross-channel operational summarization
- webhook-triggered follow-up on GitHub/Railway events
- email drafting and follow-up using the business workspace
- goals-driven research or founder task completion loops

### Coding

- Slack-launched code review or investigation requests
- remote coding task launch wrappers
- cross-VM worktree/session summaries
- "what's blocked / what should continue?" status synthesis
- Hermes-side kanban/goal support where it reduces coordination drag
- ACP/API-server experiments where they create useful reach

### Family / reservations / healthcare

- reservation search + outreach drafting
- appointment prep and reminders
- healthcare bill/EOB triage into Sheets/Docs
- family weekly planning using calendar + docs
- browser-automated admin work where portals/forms are the bottleneck

## Keep deterministic

- fleet checks
- queue hygiene
- parity checks
- canonical dispatch/controller heartbeats
- low-level transport and route resolution

## Stack synergies

This program should be designed around the user's actual stack, not around an
abstract "Hermes deployment."

### 1. Browser stack synergy

Current stack:

- Chrome browser
- Chrome DevTools MCP
- `agent-browser` CLI
- Playwright CLI backups

Best role split:

- Hermes is the operator and planner
- Chrome DevTools MCP is the first-class inspection/control surface when a live
  browser session is already useful
- `agent-browser` is the broader CLI browser lane for exploratory and
  semi-manual flows
- Playwright is the repeatable assertion-heavy fallback when a flow should
  become automated and regression-tested

High-value Hermes combinations:

- reservations: Hermes plans, browser tool executes, Gmail/Calendar close the
  loop
- healthcare portals: Hermes triages, browser tool navigates, Docs/Sheets store
  outputs
- founder research and admin tasks: Hermes reasons across Slack/Gmail/browser

### 2. Coding stack synergy

Current stack:

- Codex Desktop is the dominant coding surface
- remote SSH sessions on `epyc12` plus local macmini use are already normal
- OpenCode is the secondary coding lane

Best role split:

- Codex Desktop remains the primary interactive coding workbench
- Hermes becomes the Slack/operator/control layer around coding runs
- OpenCode becomes the preferred headless execution lane when Slack-launched or
  background coding work is needed
- remote VM execution is treated as normal, not exceptional

High-value Hermes combinations:

- Slack -> Hermes -> remote `opencode run` for delegated coding jobs
- Slack -> Hermes -> remote `codex exec` for Codex-native runs
- status, artifacts, and next-action summaries returned to Slack
- coding-goal loops that continue investigations or review passes without
  constant manual nudging

### 3. Google Workspace synergy

Current stack:

- business Gmail / Google Workspace for `fengning@stars-end.ai`

Best role split:

- Gmail is inbound/outbound business workflow state
- Calendar is planning and commitment state
- Drive/Docs/Sheets are durable artifacts and work products
- Hermes becomes the connective tissue between these surfaces and Slack/coding

High-value Hermes combinations:

- founder daily brief from Gmail + Calendar + GitHub/Railway inputs
- action-item extraction from email into Docs/Sheets/Slack
- coding or ops results emitted into docs/spreadsheets, not only chat

### 4. Finance and healthcare synergy

Current stack:

- Blue Shield CA healthcare workflows
- Mercury banking
- business Google Workspace

Best role split:

- Hermes should not be granted direct broad financial authority up front
- business Docs/Sheets become the canonical planning and reconciliation layer
- browser automation and document processing are more valuable than blind API
  access at the start

High-value Hermes combinations:

- healthcare bills/EOBs -> Sheets reconciliation -> follow-up tasks in Slack
- Mercury statement review support through exported docs/CSV-driven workflows
- tax-adjacent startup finance organization in Workspace artifacts

### 5. Infra and hosting synergy

Current stack:

- Railway hosting
- Cloudflare registrar
- 1Password dev vault via OP CLI
- many `dx-*` flows and cron jobs

Best role split:

- Agent Coordination remains the deterministic infra broadcaster
- Hermes becomes the reasoning and follow-up layer
- OP CLI remains the canonical secret source
- Railway and Cloudflare events become webhook- or MCP-fed inputs to Hermes

High-value Hermes combinations:

- deployment alerts -> Hermes diagnosis -> Slack action summary
- domain and DNS tasks -> Hermes workflow orchestration with artifact trail
- scheduled infra summaries fed from deterministic `dx-*` jobs
- explicit EODHD / pipeline-alert ingestion where market-data workflows matter

### 6. Repo and memory synergy

Current stack:

- product repos: `affordabot`, `prime-radiant-ai`, EODHD ETL/pipeline work
- aux repos: `agent-skills`, `llm-common`
- orchestration repo: `~/gascity`
- work memory: `~/beads` with central Dolt server on `epyc12`

Best role split:

- Beads remains canonical work memory and issue substrate
- Hermes built-in memory handles profile continuity and operator context
- Gas City becomes the pane and systems substrate
- repository-specific workflows stay repo-grounded and deterministic where
  appropriate

High-value Hermes combinations:

- Beads issue context + repo state + Slack request -> launch coding work
- founder and startup summaries that cut across multiple repos and pipelines
- Gas City eventually surfacing Hermes/Codex/OpenCode work as one visible
  system
- explicit `llm-common` disposition to avoid rebuilding provider/routing
  abstractions twice

### 7. Canonical VM universe synergy

Current stack:

- `macmini`
- `homedesktop-wsl`
- `epyc6`
- `epyc12`

Best role split:

- Hermes should treat multi-host execution as normal
- remote execution templates should be explicit per host capability
- `epyc12` remains central for Beads and core coding throughput
- desktop-local workflows stay local when intentionally placed there

High-value Hermes combinations:

- route coding jobs to the right host based on task type
- surface host-aware status in Slack
- keep desktop-local automations separate from remote control-plane work

## Testing strategy

This program needs a real test strategy, not just feature enablement.

### Test categories

#### 1. Contract tests

Purpose:

- prove profile boundaries, token mapping, and allowed integrations are correct

Examples:

- profile-specific env/config validation
- allowed Google Workspace assets per profile
- Slack home-channel and gateway configuration checks
- OP-secret resolution checks without printing secrets

#### 2. Integration tests

Purpose:

- prove that a whole workflow path works end to end

Required early integration paths:

1. Slack -> Hermes -> background task -> Slack reply
2. Slack -> Hermes -> remote `opencode run` -> artifact/status reply
3. Slack -> Hermes -> remote `codex exec` -> artifact/status reply
4. Hermes -> Google Workspace read/write -> Slack summary
5. Hermes -> browser automation -> structured output artifact

#### 3. Regression tests for deterministic coexistence

Purpose:

- prove Hermes additions do not break existing deterministic systems

Required checks:

- Agent Coordination alerts still route correctly
- founder briefing routing remains deterministic
- `dx-*` cron jobs still behave as before
- Codex Desktop local automation flows intentionally kept local remain local

#### 4. Safety tests

Purpose:

- prove the boundaries are real and failure modes are acceptable

Examples:

- missing token / missing scope behavior
- webhook prompt-injection handling
- remote-host unavailable behavior
- browser auth/session expiry behavior
- browser anti-bot / CAPTCHA / 2FA viability and fallback behavior
- healthcare/finance-specific "must never" enforcement tests
- governed-coding-launch checks for worktree / Feature-Key / orchestration
  compliance
- provider failure / fallback behavior

#### 5. Human acceptance tests

Purpose:

- prove the workflow is actually useful in your real life

Required acceptance lanes:

- founder startup operations
- coding dispatch and follow-up
- reservation/admin workflow
- healthcare/admin workflow

#### 6. Observability tests

Purpose:

- prove multi-hop workflows can be debugged deterministically

Examples:

- Slack -> Hermes -> SSH -> remote execution traceability
- webhook/hook failure surfacing
- background task log discoverability
- cross-host failure classification

### Observability architecture

Every multi-hop Hermes workflow should carry a correlation id.

Minimum event fields:

- `correlation_id`
- `profile`
- `source_surface` such as Slack, cron, webhook, browser, or API
- `target_host`
- `beads_id` when the workflow is task-bound
- `repo` and `worktree` when the workflow is coding-bound
- `tool_surface` such as `dx-loop`, `dx-runner`, `codex`, `opencode`,
  browser, Google Workspace, or webhook
- `artifact_refs`
- `status`
- `failure_reason`

Initial log surfaces:

- Hermes gateway/service logs on the deployment host
- per-run prompt and result artifacts for governed coding dispatch
- Slack thread reference for user-visible status
- Beads comment or artifact reference when work is task-bound
- Gas City-visible session/run metadata once pane integration begins

Retention and redaction:

- logs should be structured enough for `rg`/JSON-style inspection
- sensitive finance/healthcare payloads should be redacted or linked as
  approved artifacts rather than embedded in logs
- Phase 1 should prove one trace end to end before later workflow rollout

### Testing ladder by phase

#### Phase 1

- config and profile contract checks
- Slack gateway health
- routing/fallback dry runs
- memory/Beads coexistence checks
- deployment host and supervisor verification
- per-profile secret-access verification
- deterministic input adapter verification
- healthcare/finance guardrail enforcement tests before live data access
- observability/correlation-id smoke test

#### Phase 2

- startup Google Workspace integration tests
- founder brief acceptance run
- Gmail/Calendar/Docs/Sheets write-path proof
- EODHD / pipeline-summary ingestion proof if founder operations depend on it

#### Phase 3

- coding launch smoke tests on `epyc12` and local macmini
- Slack -> coding run end-to-end tests
- session-artifact and resume-contract tests
- MCP/API/ACP smoke tests where enabled
- governed `dx-loop` / `dx-runner` interop proof
- worktree / Feature-Key enforcement proof for Hermes-launched tasks

#### Phase 4

- browser-assisted reservation workflow acceptance test
- healthcare/admin document workflow acceptance test
- finance spreadsheet/document workflow acceptance test

#### Phase 5

- Gas City pane integration tests
- visible session inventory and launch-surface tests
- no-fake-resume-semantics verification

### First concrete test pack

The first useful test pack for this program should be only five flows:

1. Slack DM -> `/background` startup task -> Slack thread result
2. Slack channel -> coding task -> remote `opencode run` on `epyc12` -> result
3. Slack channel -> coding task -> remote `codex exec` on `epyc12` -> result
4. Gmail/Calendar/Docs/Sheets founder workflow using `fengning@stars-end.ai`
5. browser-based reservation or healthcare-admin workflow with structured
   output

If those five pass, we will have proven the substrate instead of only the
configuration.

## Cross-profile communication contract

Profiles are meant to split concerns, but the system still needs explicit
handoff rules.

Examples:

- `finance` may escalate founder-relevant startup-admin findings to `olivaw`
- `family` may escalate scheduling or healthcare-admin outputs into shared
  calendar or approved notification channels
- `coder` may escalate engineering-operational findings into `olivaw` or
  deterministic alerting lanes

Cross-profile communication should be declared, not assumed.

Transport contract:

- startup/coding operational escalations should use:
  - approved Slack thread delivery, or
  - Beads-linked work artifacts when work tracking is involved
- calendar/logistics escalations should use:
  - approved calendar and Workspace artifact updates
- sensitive finance/healthcare escalations should prefer:
  - approved Docs/Sheets/Drive artifacts first
  - bounded notification summaries second

Profiles should not silently leak context through implicit shared memory or ad
hoc hidden channels.

## Comprehensive phase plan

### Phase 0 - Platform contract

Deliver:

- full feature-family scope map
- ownership map across Hermes / Agent Coordination / Codex / OpenCode / Gas City
- data and trust boundary contract
- profile model and startup Google Workspace plan
- deployment topology and supervision contract
- sensitive-data "must never" guardrails

### Phase 1 - Hermes substrate hardening

Deliver:

- profile creation and gateway install strategy
- provider routing / fallback / credential pool plan
- hooks/webhooks/plugin architecture
- memory contract and skill strategy
- per-profile secret-access model
- Beads read/write contract
- deterministic input-consumption contract
- observability and debug contract

### Phase 2 - Startup operations rollout

Deliver:

- Google Workspace integration
- founder operations workflows
- startup cron jobs
- webhook-fed operational follow-ups
- Slack home-channel and delivery contract
- EODHD / market-data pipeline interaction contract where relevant
- `llm-common` disposition for shared provider/routing concerns

### Phase 3 - Coding operations rollout

Deliver:

- Slack -> Codex/OpenCode launch paths
- remote VM command contract
- session/result artifact contract
- goals/background patterns for coding investigations
- ACP/API/MCP evaluation for coding-side leverage
- `dx-loop` / `dx-runner` interop contract
- worktree / Feature-Key enforcement contract for Hermes-launched tasks

### Phase 4 - Family / finance / healthcare / reservations rollout

Deliver:

- family calendar and logistics workflows
- finance/admin document workflows
- healthcare/admin workflows
- browser automation flows for reservations and portals
- healthcare/finance compliance and data-handling contract
- anti-bot and browser-resilience fallback contract

### Phase 5 - Gas City orchestration integration

Deliver:

- pane-of-glass integration spec
- surfaced actions and status feeds
- session inventory strategy
- explicit boundaries between controller, pane, and operator
- host-capability and routing visibility model

### Phase 6 - Advanced optimization and expansion

Deliver:

- external memory-provider decision if needed
- advanced coding/routing automation
- optional voice/TTS evaluation
- batch-processing / data-generation use only if there is a concrete reason

## Beads Structure

Epic:

- `bd-k9rfq` - Hermes maximal integration program for Star's End workflows

Children:

- `bd-k9rfq.1` - Foundation and profile boundary contract
- `bd-k9rfq.2` - Slack, hooks, and Agent Coordination coexistence contract
- `bd-k9rfq.3` - Codex Desktop, OpenCode, and Hermes coding integration investigation
- `bd-k9rfq.4` - Gas City orchestration pane integration plan
- `bd-k9rfq.5` - Startup operations automation on Hermes
- `bd-k9rfq.6` - Family, finance, health, and reservation workflows on Hermes
- `bd-k9rfq.7` - Google Workspace business integration and artifact strategy
- `bd-k9rfq.8` - Hermes platform reliability and routing architecture
- `bd-k9rfq.9` - Hermes memory, skills, and Beads coexistence contract
- `bd-k9rfq.10` - Slack background, goals, and session operating model
- `bd-k9rfq.11` - ACP, API server, and MCP integration strategy
- `bd-k9rfq.12` - Browser automation workflows for reservations and admin
- `bd-k9rfq.13` - Webhooks, hooks, plugins, and custom-skill program

Blocking edges:

- `bd-k9rfq.1` blocks `bd-k9rfq.2`
- `bd-k9rfq.1` blocks `bd-k9rfq.3`
- `bd-k9rfq.1` blocks `bd-k9rfq.4`
- `bd-k9rfq.1` blocks `bd-k9rfq.5`
- `bd-k9rfq.1` blocks `bd-k9rfq.6`
- `bd-k9rfq.2` blocks `bd-k9rfq.5`
- `bd-k9rfq.2` blocks `bd-k9rfq.6`
- `bd-k9rfq.3` blocks `bd-k9rfq.4`
- `bd-k9rfq.1` blocks `bd-k9rfq.7`
- `bd-k9rfq.1` blocks `bd-k9rfq.8`
- `bd-k9rfq.1` blocks `bd-k9rfq.9`
- `bd-k9rfq.1` blocks `bd-k9rfq.10`
- `bd-k9rfq.1` blocks `bd-k9rfq.11`
- `bd-k9rfq.1` blocks `bd-k9rfq.12`
- `bd-k9rfq.1` blocks `bd-k9rfq.13`
- `bd-k9rfq.2` blocks `bd-k9rfq.10`
- `bd-k9rfq.2` blocks `bd-k9rfq.13`
- `bd-k9rfq.3` blocks `bd-k9rfq.10`
- `bd-k9rfq.3` blocks `bd-k9rfq.11`
- `bd-k9rfq.6` blocks `bd-k9rfq.12`
- `bd-k9rfq.7` blocks `bd-k9rfq.5`
- `bd-k9rfq.8` blocks `bd-k9rfq.11`
- `bd-k9rfq.9` blocks `bd-k9rfq.5`
- `bd-k9rfq.9` blocks `bd-k9rfq.6`
- `bd-k9rfq.10` blocks `bd-k9rfq.5`
- `bd-k9rfq.10` blocks `bd-k9rfq.6`
- `bd-k9rfq.11` blocks `bd-k9rfq.4`
- `bd-k9rfq.13` blocks `bd-k9rfq.5`
- `bd-k9rfq.13` blocks `bd-k9rfq.6`

## Validation

Validation gates for the program:

1. Profile docs and token boundaries are explicit and reviewable.
2. Google Workspace integration is configured only for approved accounts/assets.
3. Slack coexistence does not regress deterministic Agent Coordination flows.
4. At least one Slack-launched coding task path is proven end to end.
5. At least one background/goal-based Hermes workflow is proven useful.
6. At least one browser-automation workflow is proven useful.
7. Memory, skills, and Beads roles remain explicit and non-overlapping.
8. Gas City integration does not assume fake native resume semantics that do not
   exist.
9. Startup workflow candidates and personal workflow candidates are separately
   prioritized.
10. Prime Persona Tester remains on its existing local Codex Desktop automation
    lane unless a later task intentionally changes that decision.

### Phase gates

Each phase should have explicit "definition of done" checks:

- Phase 0 done:
  - deployment host is declared
  - runtime supervisor surface is declared
  - healthcare/finance "must never" rules are written
- Phase 1 done:
  - declared supervisor is verified running
  - profile secret boundaries are documented
  - profile secret access checks are verified without printing secrets
  - Beads read/write contract is documented
  - Beads read path is verified against the central runtime
  - deterministic input contract is documented
  - deterministic producer mappings are verified for the first adapter set
  - observability/debug contract is documented
  - one correlation-id trace is verified across at least Slack -> Hermes ->
    execution target
- Phase 2 done:
  - founder workflow artifacts land in the intended Workspace sinks
  - startup deterministic inputs are consumed through explicit adapters
- Phase 3 done:
  - at least one governed coding run path is proven
  - Hermes-launched coding tasks preserve worktree and Feature-Key rules
- Phase 4 done:
  - at least one browser-heavy healthcare or reservation flow has a viable
    fallback story
- Phase 5 done:
  - Gas City surfaces Hermes/Codex/OpenCode state without inventing fake shared
    session semantics

## Risks / Rollback

### Risks

- accidental overreach on data access
- Slack ownership confusion between deterministic and reasoning surfaces
- brittle command wrappers around Codex/OpenCode sessions
- premature Gas City coupling
- memory-layer sprawl if Beads/Hermes memory/provider roles are not kept clean
- webhook prompt-injection risk
- browser automation overreach or brittle anti-bot flows
- too many profiles/gateways without a clean operating model
- platform sprawl before reliability controls are in place

### Rollback

- disconnect Google Workspace scopes by profile
- disable Hermes cron/webhooks/hooks independently
- keep Agent Coordination as canonical fallback transport
- keep coding execution routable directly to Codex/OpenCode without Hermes in
  the loop
- do not migrate deterministic jobs until Hermes-added value is proven
- keep ACP/API-server adoption optional
- leave external memory providers disabled unless their value is demonstrated

Trigger conditions should also be explicit:

- repeated incorrect Workspace artifact generation on the same workflow class
- repeated governed-coding-launch failures caused by missing worktree or
  Feature-Key enforcement
- browser workflows entering anti-bot/CAPTCHA loops without a safe fallback
- healthcare/finance guardrail violations or near-misses
- repeated multi-hop observability failures where a Slack-launched run cannot be
  traced across system boundaries

## Recommended First Task

Start with `bd-k9rfq.1` - Foundation and profile boundary contract.

Why first:

- every other integration depends on explicit data, token, and profile
  boundaries
- it resolves the biggest hidden risk in "maximal integration"
- it sets the contract for what the later Slack, Google, and coding tasks are
  allowed to touch

## Proposed First Executable Deliverables

1. Define the exact role of `olivaw` vs `finance` vs `family` vs `coder`.
2. Define which Google Workspace assets each profile can access.
3. Define which Hermes feature families are phase-1, phase-2, and later.
4. Define which workflows remain deterministic and which move to Hermes.
5. Define the first coding launch/resume path to prove:
   - recommended first cut: Slack -> Hermes -> remote `opencode run` or
     `codex exec`, with artifact/session reply back to Slack
6. Define the first browser-automation and Google Workspace workflows to prove.
7. Define the initial provider-routing / fallback / credential-pool posture.
8. Define Gas City's initial integration as a surfaced orchestration pane, not
   a controller replacement.
