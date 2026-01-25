# ACFS Tools Research: Evaluation & Recommendations

**Author**: Antigravity  
**Date**: 2026-01-14  
**Repository Evaluated**: [Dicklesworthstone/agentic_coding_flywheel_setup](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup)  
**Feature-Key**: bd-acfs-research

---

## Executive Summary

The ACFS (Agentic Coding Flywheel Setup) repository is a comprehensive VPS bootstrapping system for agentic development environments. After thorough analysis, **we should adopt 2-3 tools** and **skip the rest** because our V3 DX infrastructure already covers most functionality through different mechanisms.

### Top Priority Adoptions

| Priority | Tool | Why Adopt |
|----------|------|-----------|
| 🔴 P0 | **DCG** (Destructive Command Guard) | Superior safety over git-safety-guard; Rust-based, modular packs |
| 🔴 P0 | **BV** (Beads Viewer) | Human QoL + robot-plan API for agents; integrates with lib/fleet |
| 🟡 P1 | **NTM** (Named Tmux Manager) | Local multi-agent orchestration; complements remote dispatch |
| 🟡 P2 | **CASS** (Session Search) | Long-term knowledge mining; pilot evaluation |

---

## Complete Tool Inventory

### Category 1: Shell & Terminal UX

#### zsh
- **What it does**: Default shell with plugins
- **Our equivalent**: ✅ Already use via vm-bootstrap
- **Verdict**: ❌ **SKIP** - Already have

#### fzf (Fuzzy Finder)
- **What it does**: Fuzzy file/history search
- **Our equivalent**: ✅ Already in vm-bootstrap
- **Verdict**: ❌ **SKIP** - Already have

#### zoxide (z)
- **What it does**: Smart cd, learns frequent directories
- **Our equivalent**: ✅ Already in vm-bootstrap
- **Verdict**: ❌ **SKIP** - Already have

#### eza (modern ls)
- **What it does**: Pretty ls with git status
- **Our equivalent**: Standard ls
- **Human QoL**: 🟡 Nice visual improvements
- **Agent utility**: ⚪ None (agents parse output)
- **Verdict**: ⚪ **OPTIONAL** - Nice-to-have, no priority

#### atuin (shell history)
- **What it does**: Cross-machine history sync with search
- **Our equivalent**: Standard Ctrl+R
- **Human QoL**: 🟡 Better history search
- **Agent utility**: ⚪ None
- **Verdict**: ⚪ **OPTIONAL** - Could evaluate for human workflow

---

### Category 2: Languages & Package Managers

#### bun, uv, cargo, go
- **What it does**: Language runtimes and package managers
- **Our equivalent**: ✅ All via mise in vm-bootstrap
- **Verdict**: ❌ **SKIP** - Already have

---

### Category 3: Dev Tools

#### tmux
- **What it does**: Terminal multiplexer
- **Our equivalent**: ✅ Already required
- **Verdict**: ❌ **SKIP** - Already have

#### ripgrep (rg)
- **What it does**: Fast code search
- **Our equivalent**: ✅ Already in vm-bootstrap
- **Verdict**: ❌ **SKIP** - Already have

#### ast-grep (sg)
- **What it does**: Structural code search/transform using AST patterns
- **Our equivalent**: None (we use text-based grep)
- **Human QoL**: 🟡 Precise refactoring
- **Agent utility**: ✅ Could power pattern-based bulk edits
- **lib/fleet**: Could use in specialized tasks
- **Verdict**: 🟡 **EVALUATE** - Worth testing for agent-driven refactors

#### lazygit (lg)
- **What it does**: TUI for git operations
- **Our equivalent**: git CLI
- **Human QoL**: 🟡 Visual staging
- **Agent utility**: ⚪ Agents use CLI
- **Verdict**: ⚪ **OPTIONAL** - Human preference only

#### GitHub CLI (gh)
- **What it does**: GitHub operations from terminal
- **Our equivalent**: ✅ Already required (create-pull-request skill)
- **Verdict**: ❌ **SKIP** - Already have

#### bat (pretty cat)
- **What it does**: Syntax-highlighted file viewing
- **Our equivalent**: ✅ Already in vm-bootstrap
- **Verdict**: ❌ **SKIP** - Already have

#### jq
- **What it does**: JSON processor
- **Our equivalent**: ✅ Already required
- **Verdict**: ❌ **SKIP** - Already have

---

### Category 4: Networking

#### tailscale
- **What it does**: Mesh VPN for multi-machine access
- **Our equivalent**: ✅ Already in vm-bootstrap, used by dx-dispatch and coordinator services
- **Verdict**: ❌ **SKIP** - Already have

---

### Category 5: AI Coding Agents

#### Claude Code
- **What it does**: Primary AI coding agent
- **Our equivalent**: ✅ This is us
- **Verdict**: ❌ **SKIP** - Already have

#### Codex CLI
- **What it does**: Alternative AI agent
- **Our equivalent**: ✅ Already available
- **lib/fleet**: Not a backend currently; could add CodexBackend
- **Verdict**: 🟡 **FUTURE** - Consider adding to lib/fleet

#### Gemini CLI
- **What it does**: Alternative AI agent
- **Our equivalent**: ✅ Already available
- **Verdict**: 🟡 **FUTURE** - Consider adding to lib/fleet

#### "Vibe Mode" aliases (cc, cod, gmi with bypasses)
- **What it does**: Skip safety checks for speed
- **Our equivalent**: ❌ Nakomi Protocol forbids this
- **Verdict**: ❌ **REJECT** - Violates safety principles

---

### Category 6: Cloud & Database

#### psql
- **What it does**: PostgreSQL client
- **Our equivalent**: ✅ Via Railway shell
- **Verdict**: ❌ **SKIP** - Already have

#### HashiCorp Vault
- **What it does**: Secrets management
- **Our equivalent**: Railway env vars
- **Verdict**: ❌ **SKIP** - Not needed (we use Railway)

#### Supabase CLI
- **What it does**: Supabase management
- **Our equivalent**: ❌ BANNED per user rules
- **Verdict**: ❌ **REJECT** - NO SUPABASE

#### Vercel / Wrangler
- **What it does**: Vercel/Cloudflare deployment
- **Our equivalent**: Railway
- **Verdict**: ❌ **SKIP** - Not relevant

---

### Category 7: Dicklesworthstone Stack (The Interesting Ones)

#### NTM (Named Tmux Manager) 🟡

**Repository**: [Dicklesworthstone/ntm](https://github.com/Dicklesworthstone/ntm)  
**Releases**: 7

**What it does**:
- Spawn multiple AI agents in named tmux panes
- Dashboard TUI with color-coded agent status
- Token velocity badges (tpm per agent)
- Context compaction detection
- Conflict tracking (multiple agents touching same files)
- Broadcast prompts to agent groups
- Session checkpoints

**Our equivalent**: 
- dx-dispatch / lib/fleet for remote dispatch
- slack-coordinator.py for multi-VM coordination (optional)
- No LOCAL multi-agent orchestration

**Human QoL**: ✅ **Excellent** - Visual dashboard for monitoring
**Agent utility**: 🟡 Could spawn via `ntm add` for local sessions

**lib/fleet integration**:
- NTM = LOCAL orchestration (same machine)
- lib/fleet = REMOTE orchestration (cross-VM)
- **Complementary, not replacement**
- Could add `NtmBackend` for local-only dispatch

**Verdict**: 🟡 **P1 - ADOPT for local multi-agent**

Install command:
```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash
```

---

#### UBS (Universal Build Script)

**What it does**: Auto-detect project type and run build/test

**Our equivalent**: 
- Tailored Makefile targets (make verify-local, make ci-lite)
- verify-pipeline skill
- railway-doctor skill

**Verdict**: ❌ **SKIP** - Our approach is more tailored

---

#### BV (Beads Viewer) 🔴

**Repository**: [Dicklesworthstone/beads_viewer](https://github.com/Dicklesworthstone/beads_viewer)  
**Releases**: 19 (very mature)

**What it does**:
- Kanban board view (press `b`)
- Dependency graph visualization (press `g`)
- PageRank + centrality analysis for bottleneck detection
- Live reload on `.beads/issues.jsonl` changes
- Time-travel to compare against git revisions (press `t`)
- Fuzzy search (press `/`)
- Sprint dashboard with burndown
- **Robot Protocol**: `bv --robot-plan`, `bv --robot-insights`

**Our equivalent**:
- `bd` CLI for Beads operations
- No visualization
- No robot protocol

**Human QoL**: ✅ **Excellent**
- Visual workflows humans can understand
- Automated impact scoring
- Graph-based bottleneck detection

**Agent utility**: ✅ **Excellent**
- `bv --robot-plan` returns structured next-action JSON
- `bv --robot-insights` for graph metrics
- Offloads graph traversal from LLM to deterministic tool

**lib/fleet integration**:
```python
# FleetDispatcher could use BV for auto task selection
def auto_select_task(self) -> Optional[str]:
    result = subprocess.run(["bv", "--robot-plan"], capture_output=True)
    plan = json.loads(result.stdout)
    return plan.get("next")
```

**agent-skills integration**:
- Enhance `beads-workflow` skill with BV robot protocol
- Add `bv --robot-plan` as alternative to `bd list --open`

**Verdict**: 🔴 **P0 - MUST ADOPT**

Install command:
```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh | bash
```

---

#### CASS (Coding Agent Session Search) 🟡

**Repository**: [Dicklesworthstone/coding_agent_session_search](https://github.com/Dicklesworthstone/coding_agent_session_search)  
**Releases**: 32 (very active)

**What it does**:
- Unified search across all agent sessions (Claude, Codex, Cursor, etc.)
- Local semantic search with MiniLM embeddings
- Sub-60ms query latency
- Timeline view ("what did I work on today?")
- Robot mode for agent-to-agent knowledge transfer
- Bookmarks and saved views

**Our equivalent**: None

**Human QoL**: ✅ "I solved this before" search
**Agent utility**: ✅ Robot mode for cross-session learning

**lib/fleet integration**:
- FleetMonitor could log in CASS-indexable format
- Session archaeology for debugging

**llm-common integration**:
- CASS uses MiniLM embeddings
- Could share embedding infrastructure

**Caveats**:
- Requires indexing setup
- Value accumulates over time (slow payoff)
- We delete conversation history frequently

**Verdict**: 🟡 **P2 - PILOT** - Install on epyc6, evaluate for 1 month

Install command:
```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh | bash
```

---

#### CM (Claude Memory)

**What it does**: Persistent memory for Claude agents

**Our equivalent**:
- GEMINI.md / AGENTS.md files
- Area context skills
- Serena cached summaries

**Verdict**: ❌ **SKIP** - Our approach may be better

---

#### CAAM (Claude Auth Switcher MCP)

**What it does**: Switch credentials per project

**Our equivalent**: Single org credentials, Railway env separation

**Verdict**: ❌ **SKIP** - Not relevant

---

#### SLB (Safety Lockbox)

**What it does**: Emergency brake for nuclear operations

**Our equivalent**: git-safety-guard skill

**Verdict**: 🟡 **REPLACED BY DCG** - DCG is the Rust successor

---

#### DCG (Destructive Command Guard) 🔴

**Repository**: [Dicklesworthstone/destructive_command_guard](https://github.com/Dicklesworthstone/destructive_command_guard)  
**Releases**: 7

**What it does**:
- Rust-based hook for Claude Code PreToolUse
- Blocks dangerous commands:
  - `git reset --hard`, `git checkout -- <files>`
  - `rm -rf` (except /tmp)
  - `git push --force`
  - `git clean -f`, `git branch -D`
  - `git stash drop/clear`
- **Modular pack system**:
  - `database.*` - DROP TABLE, TRUNCATE
  - `kubernetes.*` - kubectl delete
  - `cloud.*` - aws/gcloud destructive ops
  - `containers.*` - docker rm -f
- Gemini CLI support (not just Claude)
- Sub-millisecond latency (Rust)
- Allowlist for safe patterns

**Our equivalent**: git-safety-guard (Python)

**Comparison**:
| Feature | DCG | git-safety-guard |
|---------|-----|------------------|
| Language | Rust | Python |
| Latency | <1ms | ~50ms |
| Patterns | 50+ with packs | ~12 core |
| Database protection | ✅ | ❌ |
| K8s protection | ✅ | ❌ |
| Cloud protection | ✅ | ❌ |
| Gemini support | ✅ | ❌ |

**Human QoL**: ✅ Peace of mind
**Agent utility**: ✅ **Critical** - All dispatched agents protected

**lib/fleet integration**: Install on ALL target VMs (epyc6, macmini)

**Verdict**: 🔴 **P0 - MUST ADOPT - Replace git-safety-guard**

Install command:
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/install.sh?$(date +%s)" | bash
```

Configuration (`~/.claude/settings.json`):
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "dcg"}]
      }
    ]
  }
}
```

---

#### RU (Repo Updater)

**What it does**:
- Multi-repo sync (clone, pull, detect conflicts)
- `agent-sweep`: AI-driven commits across dirty repos
- Work-stealing queue for parallel execution

**Our equivalent**:
- sync-feature-branch for single repo
- No multi-repo automation

**Human QoL**: 🟡 Keep all repos synced
**Agent utility**: ✅ agent-sweep for bulk commits

**lib/fleet integration**: Post-completion hook for multi-repo commits

**Caveats**:
- Only useful if managing many repos becomes painful
- We have 4 repos: agent-skills, llm-common, affordabot, prime-radiant

**Verdict**: 🟡 **P3 - EVALUATE LATER** - Monitor need

---

### Category 8: Bundled Utilities

#### giil (Get Image from Internet Link)

**What it does**: Download images from iCloud links to terminal

**Human QoL**: 🟡 Mobile debugging workflow
**Agent utility**: 🟡 Could analyze downloaded screenshots

**Verdict**: ⚪ **OPTIONAL** - Nice-to-have for mobile debugging

---

#### csctf (Chat Shared Conversation to File)

**What it does**: Convert AI conversation links to Markdown

**Human QoL**: 🟡 Archive conversations
**Agent utility**: 🟡 CASS input

**Verdict**: ⚪ **OPTIONAL** - Knowledge management

---

### Category 9: MCP Agent Mail

**What it does**: Multi-agent messaging and file reservations via MCP

**Our equivalent**: slack-coordinator.py (639 lines) with:
- Multi-VM routing (@epyc6, @macmini)
- Git worktree per Beads issue
- Jules dispatch integration
- Human approval workflow

**Status**: User reported buggy ~30 days ago

**Verdict**: ❌ **REJECT** - Slack is simpler and more reliable

---

## Priority Summary

### 🔴 P0 - Must Adopt (This Week)

| Tool | Why | Install |
|------|-----|---------|
| **DCG** | Critical safety, superior to git-safety-guard | [install.sh](https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/install.sh) |
| **BV** | Human QoL + robot-plan API for lib/fleet | [install.sh](https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh) |

### 🟡 P1 - Should Evaluate (This Month)

| Tool | Why | Install |
|------|-----|---------|
| **NTM** | Local multi-agent orchestration | [install.sh](https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh) |

### 🟡 P2 - Pilot Project (Next Month)

| Tool | Why | Install |
|------|-----|---------|
| **CASS** | Cross-session knowledge mining | [install.sh](https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh) |

### 🟡 P3 - Future Consideration

| Tool | Why | Trigger |
|------|-----|---------|
| **ast-grep** | Pattern-based refactoring | When we need bulk AST transforms |
| **RU** | Multi-repo sync | When managing 4+ repos becomes painful |

### ❌ Skip

| Tool | Why |
|------|-----|
| All shell tools | Already have via vm-bootstrap |
| All language managers | Already have via mise |
| Agent Mail | Buggy, Slack is better |
| Vibe mode aliases | Violates Nakomi Protocol |
| Supabase | BANNED per user rules |
| Vault/Vercel/Wrangler | Use Railway |

---

## Appendix: Source Links

| Tool | Repository |
|------|------------|
| DCG | https://github.com/Dicklesworthstone/destructive_command_guard |
| BV | https://github.com/Dicklesworthstone/beads_viewer |
| NTM | https://github.com/Dicklesworthstone/ntm |
| CASS | https://github.com/Dicklesworthstone/coding_agent_session_search |
| ACFS | https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup |
