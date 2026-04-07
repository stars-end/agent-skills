# Beads Runtime Architecture Review

## 1. Do we need `~/bd` at all under a centralized Dolt server model?

No. A centralized Dolt server model inherently decouples the database frontend from a local git repository checkout. The upstream Beads system is fundamentally bound to the Dolt database (`.beads/dolt/`), not a general `.git` directory. The current usage of a `~/bd` clone merely anchors the runtime via `BEADS_DIR`, but comes with the baggage of being an independent git checkout that agents repeatedly confuse for control-plane status, or try to cleanly commit within.

## 2. What does upstream Beads most naturally want us to do?

According to `README.md` (`Git-Free Usage`) and `DOLT.md`, Beads is perfectly comfortable operating as a detached SQL tracker with git-integration intentionally disabled. By combining the environment variable `export BEADS_DIR=/path/to/standalone-dir/.beads` with `bd init --stealth` (which toggles `no-git-ops: true` in `.beads/config.yaml`), upstream Beads can natively act as a standalone daemon decoupled from version control workflows.

While the "Shared Server" mode is also heavily featured, it natively separates databases by repository string prefix. The `~/.beads/shared-server/` capability isolates each project's issues, deliberately preventing cross-project linking or a unified backlog view. Since the team heavily relies on a single centralized graph interface across multiple VMs ("one canonical ~/bd project for cross-VM / cross-repo usage"), the native multi-project Shared Server feature directly contradicts the required graph architecture.

## 3. Evaluation of Options

### Option A: Dedicated non-git Beads runtime directory
*e.g., `BEADS_DIR=~/.beads-runtime/.beads` + `bd init --stealth`*
- **Robustness**: High. Completely insulates the tracker's storage and operations from git branching drift, uncommitted file panics, and accidental repository mutability.
- **Founder Cognitive Load**: Low. Single global endpoint. No questions about checking out branches or committing PRs to maintain the hub's state. 
- **Agent Confusion**: Best. The complete removal of an overarching `.git` directory guarantees that an agent cannot misinterpret "git clean" as "tracker healthy", and structurally prevents any attempt to merge tracking issues recursively into standard PR flows.

### Option B: Upstream-native multi-project (Shared Server mode)
*e.g., per-project prefixes across `~/.beads/shared-server/`*
- **Robustness**: High. Uses explicit port conflict avoidance logic and standard operations.
- **Founder Cognitive Load**: High. Would necessitate fragmented tracking. Linking an Epic in `prime-radiant-ai` to track ops in `agent-skills` becomes completely impossible inside a single graph.
- **Agent Confusion**: Moderate. Eliminates `~/bd` checkout drift, but introduces fragmented tool discovery and requires agents to properly understand mapping prefixes to correctly read state.

### Option C: Keep canonical `~/bd` + Wrappers
*e.g., using strictly locked APIs, read-gates, and error wrappers.*
- **Robustness**: Moderate. Will eternally rely on bespoke wrappers to coerce correct directory-specific behavior over default agent tendencies.
- **Founder Cognitive Load**: Moderate/High. Recurring long-term tax on writing and troubleshooting these defensive wrappers.
- **Agent Confusion**: Highest. Agents inevitably bypass wrappers given an edge case, repeatedly tripping over the fact that `~/bd` is a valid but distracting git repository.

## 4. Recommendation and Migration Path

**Recommendation:** Migrate to a **Dedicated non-git Beads runtime directory** (Option A).

### Target Model
- Move the backend target completely out of `~/bd` (a user-space git clone).
- Store the Dolt database at a dedicated user-level or system-level path explicitly decoupled from user checkouts, e.g., `~/.beads-runtime/`.
- Ensure this backend maintains `<runtime-dir>/.beads/config.yaml` with `no-git-ops: true`, configured via `bd init --stealth`.
- Globally update `BEADS_DIR` on all nodes (hub and spokes) to point at this `<runtime-dir>/.beads/`.

### What changes first?
1. Provision the new static directory on the `epyc12` hub.
2. Turn off the active `beads-dolt` systemd service gracefully. 
3. Perform a data lift-and-shift by executing `bd backup sync` or copying the explicit database tree from `~/bd/.beads/dolt/` to `<runtime-dir>/.beads/dolt/`.
4. Run `bd init --stealth` targeting the new `<runtime-dir>` to ensure the `config.yaml` schema commits to git-free operations without overwriting the Dolt data.
5. Remap `BEADS_DIR` in `.zshrc`/profiles and the relevant systemd units to target `<runtime-dir>/.beads`.
6. Bring the service back up and run `beads-dolt dolt test --json` to verify.

### What should explicitly NOT be changed yet?
- Do not dismantle or delete the existing `~/bd` repository; it should remain entirely untouched and decoupled, functioning as an instant rollback target or historical safety net.
- Do not migrate the port (`3307`), existing server connection strings, or systemd daemon semantics.
- Do not attempt to transition into the "Shared Server" capability or restructure the schema into multiple discrete databases.

## 5. Remaining Tradeoffs

- **Backup mechanism changes**: The tracker will no longer benefit from implicit local git commits matching the repository source tree. Backing up issue logs explicitly shifts out-of-band, relying strictly on native Dolt branch tracking (`bd vc log`), Dolt pushes to a remote (`dolt push`), and cron-scheduled `bd backup sync`.
- **Global Context Disconnect**: Ad-hoc file path references embedded inside issues or PR tracking graphs will lack a shared monolithic "root" orienting context across agents. Paths will have to be globally resolvable or absolute.
