# Hermes Feature and Workstream Matrix

Feature-Key: `bd-k9rfq`

This matrix translates Hermes feature families into the actual Star's End
program scope.

| Feature family | In scope | Primary owner | Primary profiles | Phase | Notes |
| --- | --- | --- | --- | --- | --- |
| Slack messaging | Yes | Hermes | `olivaw`, `coder`, `family`, `finance` | 1-2 | Home-channel and thread model must coexist cleanly with Agent Coordination |
| Background tasks | Yes | Hermes | all | 2-3 | Required for non-blocking startup and coding work |
| Persistent goals | Yes | Hermes | `olivaw`, `coder` | 2-3 | Best for bounded iterative work, not deterministic controllers |
| Cron / scheduled tasks | Yes | Hermes | all | 2-4 | Founder, coding, family, finance, healthcare, reservations |
| Sessions / resume | Yes | Hermes + coding tools | `olivaw`, `coder` | 2-3 | Distinguish Hermes sessions from Codex/OpenCode sessions |
| Deployment topology / supervision | Yes | Shared | `olivaw`, `coder` | 0-1 | Declare runtime hosts and supervisors before rollout |
| Kanban / board workflows | Yes | Hermes | `olivaw` | 3 | Operator clipboard only: intake, reminders, blocked cards, followups, handoff visibility |
| Subagent delegation | Yes, bounded | Hermes | `olivaw` | 3 | Read-only reasoning and non-coding follow-through only in this lane |
| Execute-code workflows | Deferred/external | BD Symphony | `coder` | final | Owned by BD Symphony/Gas City/dx-*; Hermes only consumes signed-off artifacts later |
| Google Workspace | Yes | Hermes | `olivaw`, `family`, `finance` | 2-4 | Business workspace first: `fengning@stars-end.ai`; personal account is calendar-view only by default |
| Gmail | Yes, bounded | Hermes | `olivaw`, later `finance` | 2+ | Startup mailbox first; keep personal Gmail separate; finance mailbox access deferred |
| Calendar | Yes | Hermes | `olivaw`, `family` | 2-4 | Business calendar can be shared into personal GCal for unified planning visibility |
| Drive / Docs / Sheets | Yes | Hermes | all | 2-4 | Canonical artifacts for planning, healthcare, finance, follow-up |
| Contacts | Yes | Hermes | `olivaw`, `family` | 2-4 | Useful for outreach, reservations, logistics |
| Browser automation | Yes | Hermes | `family`, `finance`, `olivaw` | 4 | Reservations, healthcare portals, admin-heavy workflows |
| Vision / image handling | Yes | Hermes | all | 2-4 | Useful for healthcare docs, receipts, screenshots, bills |
| Voice / TTS | Later | Hermes | `family` | 6 | Nice-to-have, not early critical path |
| Hooks | Yes | Hermes | all | 1-2 | Core extension and guardrail surface |
| Webhooks | Yes | Hermes | `olivaw`, `coder` | 2-3 | GitHub, Railway, startup workflows, possible finance/admin intake |
| Plugins | Yes | Hermes | all | 2-3 | Especially for custom behavior and surface packaging |
| Custom skills | Yes | Hermes | all | 2-4 | High-value specialization lane for this stack |
| Memory (built-in) | Yes | Hermes | all | 1-2 | Profile continuity memory |
| Memory providers (external) | Later | Hermes | maybe `family`, maybe `finance` | 6 | Do not replace Beads; prove need first |
| Beads interop | Yes | Shared | `coder`, `olivaw` | 1-2 | Beads remains canonical work memory |
| Beads read/write contract | Yes | Shared | `coder`, `olivaw` | 1 | Query/write boundaries must be explicit |
| MCP integration | Yes | Hermes | `coder`, `olivaw` | 3 | Main way to integrate tools and internal APIs cleanly |
| MCP inventory | Yes | Shared | `coder`, `olivaw` | 1-3 | Inventory Chrome DevTools, Serena, GitHub, Google, Railway, Beads surfaces before wiring |
| ACP integration | Yes | Hermes | `coder` | 3 | Useful for editor surfaces, less central than Codex Desktop |
| API server | Yes | Hermes | `coder`, `olivaw` | 3-5 | Strong fit for Gas City and internal tooling |
| Provider routing | Yes | Hermes | all | 1-2 | Needed as Hermes becomes real infrastructure |
| Fallback providers | Yes | Hermes | all | 1-2 | Reliability feature, not optional if usage grows |
| Credential pools | Yes | Hermes | all | 1-2 | Reliability and quota management feature |
| Per-profile secret access | Yes | Shared | all | 1 | OP CLI usage and injected-runtime boundaries must be explicit |
| Codex Desktop launch/resume interop | Yes, partial | Shared | `coder` | 3 | Launch/resume via CLI and artifacts now; native desktop-resume bridge unproven |
| OpenCode interop | Yes | Shared | `coder` | 3 | Strong headless lane for Slack-launched jobs |
| Governed coding dispatch | Deferred/external | BD Symphony | `coder` | final | dx-* primitives/configs are BD Symphony-owned; Hermes waits for signoff |
| Worktree / Feature-Key enforcement | Deferred/external | BD Symphony | `coder` | final | Owner-provided execution contract; Hermes never writes repos directly |
| Coding launch prompt artifacts | Deferred/external | BD Symphony | `coder` | final | Hermes may pass `source_bdx` and operator intent after signoff |
| Remote SSH execution | Deferred/external | BD Symphony | `coder` | final | Canonical VM execution remains outside this lane |
| Gas City pane integration | Deferred/external | BD Symphony | `coder`, `olivaw` | final | Olivaw verifies visibility after owner signoff; does not implement pane/runtime |
| Agent Coordination coexistence | Yes | Shared | `olivaw`, `coder` | 1-2 | Deterministic transport stays there |
| Deterministic `dx-*` input adapters | Yes | Shared | `olivaw`, `coder` | 1-2 | Hermes must consume explicit artifacts, not scrape ad hoc surfaces |
| Deterministic producer mapping | Yes | Shared | `olivaw`, `coder` | 1-2 | Map named producers to current surfaces, including `#railway-dev-alerts` and `#fleet-events` |
| Healthcare workflows | Yes | Hermes | `finance`, `family` | 4 | Use docs/sheets/browser before broad inbox expansion |
| Healthcare/finance guardrails | Yes | Shared | `finance`, `family`, `olivaw` | 0-1 | Write down the "must never" rules before granting data access |
| Healthcare/finance technical security | Yes | Shared | `finance`, `family`, `olivaw` | 0-1 | Define redaction, retention, audit trail, and approved artifact sinks |
| Restaurant reservations | Yes | Hermes | `family` | 4 | Browser automation + Gmail/Calendar is the useful combo |
| Startup founder operations | Yes | Hermes | `olivaw` | 2 | One of the highest-ROI early lanes |
| EODHD / pipeline integration | Yes | Shared | `olivaw`, `coder` | 2 | Start from existing summaries in `#railway-dev-alerts`; Hermes summarizes/routes, not owns alerts |
| `llm-common` disposition | Yes | Shared | `coder`, `olivaw` | 2 | Align with LiteLLM + Pydantic AI migration and DeepSeek V4 default path |
| Observability / traceability | Yes | Shared | all | 1-3 | Multi-hop debugging must be designed, not discovered |
| Correlation-id log contract | Yes | Shared | all | 1 | Required for Slack -> Hermes -> host/tool traceability |
| Cross-profile communication | Yes | Shared | all | 2-4 | Escalation and artifact handoff between profiles must be explicit |
| Rollback trigger conditions | Yes | Shared | all | 1-4 | Safety rollback should be governed by explicit triggers, not panic |
| Code factory integration (`~/gascity`) | Deferred/external | BD Symphony | `coder` | final | BD Symphony agent owns; Olivaw consumes only signed-off artifacts |

## Phase intent

- Phase 0-1: boundaries, profiles, routing, memory, hooks, coexistence
- Phase 2: startup operations + Google Workspace backbone
- Phase 3: Slack/background/goals + non-coding Hermes skills; coding orchestration is external/final
- Phase 4: family, finance, healthcare, reservations, browser-heavy workflows
- Final phase: Gas City/BD Symphony/dx-* consumption after BD Symphony signoff
- Phase 6: advanced optimization and optional expansion
