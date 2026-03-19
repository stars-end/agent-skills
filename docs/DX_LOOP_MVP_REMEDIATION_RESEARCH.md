# DX-Loop MVP Remediation Research: A "Fresh Eyes" Re-evaluation

## 1. Executive Summary
A critical re-evaluation of the `dx-loop` execution experiment (PR [#366](https://github.com/stars-end/agent-skills/pull/366)) reveals that simply fixing control-plane bugs (launch failures, state truthfulness) is **necessary but insufficient** to match the reliability and usefulness of in-session subagents. 

The subagent process succeeded because it utilized **dynamic model selection, immediate human steering, seamless local takeover, and contextual branch-stack awareness**. `dx-loop`, by contrast, operated as a rigid, monolithic black box. To make `dx-loop` genuinely usable for founder-facing product work, the MVP must move beyond bug fixes and explicitly bridge these architectural capability gaps.

## 2. Evidence Base & Subagent Success Factors
Primary artifacts inspected:
- **Retrospective:** `docs/DX_LOOP_PRODUCT_EXECUTION_RETROSPECTIVE.md` (PR #366)
- **ADR:** `docs/adr/ADR-DX-LOOP-V1.md`
- **Beads Items:** `bd-5w5o.16` through `.27`, `bd-ppt4`, `bd-aoy1`

**Why Subagents Won (From the Retro):**
1. Deliberate model choice per task (e.g., strong models for contracts, fast models for coding).
2. Immediate steering when agents drifted.
3. Easy local takeover when tasks stalled.
4. Preserved momentum across stacked PR branches and CI friction.

## 3. Comprehensive Failure Taxonomy & Architectural Gaps

| Artifact/Symptom | The Subagent Advantage | The `dx-loop` Gap | Required MVP Remediation |
|---|---|---|---|
| `bd-5w5o.17`, `.20`, `.22` (State reporting bugs) | Transparent session context. | **Opaque State:** `dx-loop` misreported failed/blocked runs as healthy, hiding reality. | **Truthful Operator States:** Fix the state machine to expose immediate start/bootstrap races. |
| `bd-5w5o.23`, `.26` (Preflight & launch crashes) | Operator sees local execution fail immediately. | **Brittle Launch Harness:** Silent quick-fails (`monitor_no_rc_file`) broke the unattended promise. | **Stable Default Execution Lane:** Hardened `dx-runner` preflights; fail loud and early. |
| Narrative: "Model choice was deliberate per task" | Humans route complex tasks to Claude/GPT and simple tasks to OpenCode. | **Monolithic Provider Routing:** `dx-loop` forces `provider: opencode` globally. | **Phase/Task-Aware Routing:** Support dynamic providers (e.g., `review_provider: cc-glm`, `impl_provider: opencode`). |
| Narrative: "Steering and Local Takeover" | Founder can pause an agent, fix a typo, and resume. | **Rigid Execution Cycle:** No mechanism for human intervention without breaking the orchestrator state. | **Human-in-the-Loop Takeover:** Add `dx-loop hijack` or `resolve` to let humans manually inject PR artifacts for stalled tasks. |
| `bd-aoy1`, `bd-ppt4` (Prompt & Baton weakness) | Human naturally bases their PR on the upstream PR branch. | **DAG-to-Git Disconnect:** Knows dependencies but doesn't inject upstream PR branches into worktree initialization. | **Stacked PR Awareness:** Inject dependency PR branches into the implementer prompt & bootstrap. |

## 4. Re-Evaluating Provider & Model Quality
**Is `glm-5` (OpenCode) the primary blocker?**
*No, but monolithic routing is.* `glm-5` appears acceptable for bounded implementation work, pending a clean MVP test. However, it struggles with complex contract-setting and multi-step architectural review. 

The failure was forcing `glm-5` to do *everything* unattended. A bulletproof `dx-loop-mvp` must allow the orchestrator to dispatch implementation to the fast OpenCode lane while utilizing a stronger model (like `cc-glm` or an Anthropic-based runner) for the Review/Validation baton.

## 5. What Belongs In a "Bulletproof" `dx-loop-mvp`
To truly rival the subagent process, the MVP must deliver:
1. **Stable & Truthful Harness:** Fix `dx-runner` launch crashes and `dx-loop` state misreporting.
2. **Dynamic Baton Routing:** Allow the configuration or prompt artifact to specify different providers for Implement vs. Review.
3. **Explicit Takeover Escape Hatch:** A CLI command (e.g., `dx-loop bypass <task-id> --pr-url <url> --sha <sha>`) that allows the founder to take over a failing task, merge it manually, and hand the baton back to the loop.
4. **Stacked-PR Git Bootstrap:** The implementer prompt MUST explicitly instruct the agent to checkout/rebase off the dependency's `PR_HEAD_SHA`, preventing master-branch merge conflicts.
5. **Structured Review Handoffs:** Auto-dispatch review only after a successful implement run, requiring concrete file references and a deterministic verdict.

## 6. Smallest Credible Acceptance Tests
To achieve a clean signal, the MVP acceptance must be split into two separate tests.

### Test A: Unattended Default-Path Wave
A single stacked product wave (e.g., 2 tasks, where Task B depends on Task A).
1. **Task A:** Implemented by OpenCode, reviewed by `cc-glm`, and reaches merge-ready.
2. **Task B:** Implemented by OpenCode (correctly branching off Task A's PR branch), reviewed, forced into 1 automated revision loop, and reaches merge-ready.
3. **Conclusion:** Wave exits gracefully without any founder babysitting, proving the original unattended gap is closed.

### Test B: Human Takeover / Resume Path
A single task wave designed to stall or fail.
1. **Task A:** Implemented by OpenCode, but the operator intentionally intervenes during the revision phase.
2. **Takeover:** The operator uses the `dx-loop bypass` (or equivalent) command to manually inject a PR artifact and resolve the task.
3. **Conclusion:** The orchestrator correctly adopts the manual resolution and exits cleanly, proving the glass-box escape hatch works.

## 7. Recommended Remediation Sequence
1. **Fix the Foundation (Harness & State):** Resolve preflight crashes (`bd-5w5o.26`) and truthful blocker reporting.
2. **Add the Escape Hatch (Takeover):** Implement the manual PR injection/bypass command so operators never feel trapped by the loop.
3. **DAG-to-Git Prompting:** Update the prompt builder to inject upstream branch names/SHAs.
4. **Dynamic Routing (Implement vs. Review):** Enable the loop to call different providers for different phases.
5. **Execute the Acceptance Tests (Test A and Test B).**

## 8. Final Recommendation
The current plan was too focused on making `dx-loop` a bug-free black box. To succeed, `dx-loop` must become a **"glass box"**—truthful about failures, capable of delegating to different models based on phase complexity, and easily hijackable by a human operator when momentum stalls. Execute the expanded MVP plan to bridge the gap between unattended automation and subagent-level pragmatism.
