# 2026-04-08 Decision Memo: Editing Layer for Coding Agents

## 1) Problem Statement
We need a final, editing-only architecture decision for coding agents. Prior memos mixed retrieval and editing, which obscured the real question: what editing surface gives the best safety and reliability under autonomous execution constraints.

This memo evaluates editing/refactor candidates independently from analysis/retrieval.

## 2) Why Prior Memos Were Insufficient for Editing
Prior memos (PRs #490, #492, #501) had three gaps specific to editing:
1. They mixed editing conclusions with retrieval outcomes.
2. They asserted brittleness claims (especially for `ast-grep`) without enough tool-level differentiation.
3. They under-specified failure visibility and first/second-attempt reliability, which are central for autonomous agents.

## 3) Current Reference Point: What `serena` Provides
`serena` is an MCP-mediated symbolic editing system built on LSP or JetBrains backends. It exposes high-level tools including `rename_symbol`, `replace_symbol_body`, `insert_after_symbol`, `insert_before_symbol`, and `find_referencing_symbols`.

Key properties:
- Symbol-level edit APIs instead of line/regex primitives.
- Rename/refactor support delegated to language tooling backends.
- Runtime dependency burden: MCP client hydration + language server/IDE backend correctness.

## 4) Candidate Set (Editing Layer Only)
Required baseline candidates:
1. `serena` (MCP, symbolic editing)
2. `ast-grep` (CLI AST structural rewrite)
3. Unified diff / patch workflow
4. `sed`/`awk`/regex editing
5. Additional CLI-native candidates:
- `comby` (structural search/replace templates)
- `jscodeshift` (codemod runner for JS/TS)
6. Architectural option: `no_dedicated_tool`

## 5) Shortlist Matrix (full/partial/none)

| Candidate | Symbol-aware edits | Rename/refactor safety | Insertion-point awareness | Precision under autonomous use | Scriptability/determinism | Failure visibility | Reliability <=2 attempts | Runtime dependency burden |
|---|---|---|---|---|---|---|---|---|
| `serena` | full | full | full | partial | partial | partial | partial | MCP/client + backend heavy |
| `ast-grep` | partial | partial | partial | partial | full | partial | partial | low (CLI-native) |
| `comby` | partial | none | partial | partial | full | partial | partial | low (CLI-native) |
| `jscodeshift` | partial (JS/TS only) | partial (codemod-specific) | partial | partial | full | full | partial | medium (Node + transform code) |
| Unified diff / patch | none | none | partial | partial | full | full | partial | very low |
| `sed` / `awk` / regex | none | none | none | none | full | partial | none | very low |
| `no_dedicated_tool` (patch-first discipline) | none | none | partial | partial | full | full | partial | very low |

Notes on scoring:
- `serena` scores highest on symbolic capability, but runtime reliability is constrained by MCP/client/backend readiness.
- `ast-grep` and `comby` provide structural matching, but neither provides cross-language symbol graph refactors equivalent to IDE/LSP rename semantics.
- `jscodeshift` is strong for JS/TS codemod programs, but it is transform-authoring heavy and language-limited.

## 6) Candidate Deep Dives

### 6.1 `serena`
Theoretical capability:
- Best available symbol-aware editing surface among evaluated options.
- Provides direct tools for symbol body replacement and symbol insertion points.

Operational reality:
- Depends on MCP runtime availability and backend health (language servers or JetBrains plugin).
- Reference quality can vary by backend/language; tool behavior is mediated by backend indexing correctness.

Implication:
- Best precision when runtime is healthy, but not CLI-pure.

### 6.2 `ast-grep`
Theoretical capability:
- Strong AST-aware rewrite system with code-pattern matching and YAML rule/fix workflows.
- Deterministic CLI execution.

Operational reality for autonomous agents:
- Precision depends on correct pattern/rule authoring and language-specific AST expectations.
- Common failures are no-match or wrong-match from pattern scope mismatch, often requiring iterative debugging.

Implication:
- Good mechanical rewrite engine, but not a drop-in symbol refactor platform.

### 6.3 `comby`
Theoretical capability:
- Language-aware structural templates with lower syntax burden than raw regex.
- Better than regex for nested structures and multiline edits.

Operational reality:
- Not symbol-graph-aware; semantics are structural/template-level.
- Safer than regex for many transforms, but still not equivalent to symbol-aware rename/refactor.

Implication:
- Useful middle ground between regex and AST tooling for scripted transformations.

### 6.4 `jscodeshift`
Theoretical capability:
- High control over JS/TS codemods with explicit transforms.
- Strong dry-run and fail-on-error operational controls.

Operational reality:
- Requires authored transforms (higher implementation effort).
- Language-scoped to JS/TS ecosystems.

Implication:
- Excellent for planned migrations in JS/TS repos, not a universal editing default.

### 6.5 Unified diff / patch
Theoretical capability:
- Minimal abstraction, universally available, highly deterministic.

Operational reality:
- No semantic awareness; safety comes from disciplined review/validation, not tool intelligence.

Implication:
- Strong baseline fallback and auditability layer.

### 6.6 `sed` / `awk` / regex
Theoretical capability:
- Fast and deterministic for simple line-oriented edits.

Operational reality:
- Fragile for scoped code transforms; high false-match/under-match risk in large codebases.

Implication:
- Keep as control tool only, not default editing surface for non-trivial refactors.

## 7) Failure Modes Under Autonomous Use
Most impactful failure modes observed across tools:
1. Symbol-graph blind edits (`patch`/`sed`) causing incomplete refactors.
2. Silent no-match or scope mismatch (`ast-grep`/`comby`) due to pattern assumptions.
3. Runtime mediation failures (`serena`) from MCP or backend readiness rather than edit semantics.
4. Transform authoring burden (`jscodeshift`) delaying small-task velocity.

Failure visibility ranking (best to worst):
- `jscodeshift` / `patch` (explicit summaries/diffs)
- `ast-grep` / `comby` (visible if diff-first discipline is enforced)
- `sed`/regex (easy to run, easy to mis-scope)

## 8) Rejected Candidates and Why
- `sed`/regex as default editor: rejected due to low semantic safety.
- `ast-grep` as sole default replacement for `serena`: rejected due to iterative rule-authoring overhead and weaker symbol-refactor semantics.
- `jscodeshift` as universal default: rejected due to language scope and transform authoring tax.

## 9) Best Theoretical Capability vs Best Operational Fit
Best theoretical capability:
- `serena` (symbol-aware APIs over language tooling backends).

Best operational fit (current environment):
- Keep `serena` for high-risk symbol-aware edits.
- Default operational path for routine changes remains patch/diff-first CLI discipline.
- Use `ast-grep`/`comby`/`jscodeshift` as targeted specialist tools, not universal defaults.

## 10) Final Recommendation (Editing Layer)
Recommendation: **narrow**.

`narrow` means:
1. Keep `serena` as the dedicated editing tool for symbol-aware/high-risk refactor tasks.
2. Standardize patch/diff-first CLI workflow as the universal fallback and default for simple edits.
3. Treat `ast-grep`, `comby`, and `jscodeshift` as opt-in specialist tools for mechanical rewrite classes.
4. Do not force strict CLI-only editing at this time; that would materially degrade refactor safety.

Why this recommendation:
- It preserves highest available editing precision where it matters (`serena`).
- It avoids over-claiming that CLI structural tools currently provide reliable symbol-level parity.
- It keeps deterministic, auditable fallback paths for all environments.

## 11) Composition With Separate Analysis Tool
The editing decision composes cleanly with a separate analysis layer:
- Analysis can evolve independently (`llm-tldr`, `grepai`, `ck`, etc.).
- Editing remains a narrow, safety-first lane anchored on symbol-aware operations when available and patch-based discipline otherwise.
- Analysis replacement work should not block editing policy.

## 12) Sources
Primary sources used:
- Serena docs/tools: https://oraios.github.io/serena/01-about/035_tools.html
- Serena repository: https://github.com/oraios/serena
- Serena issue evidence (reference behavior variability): https://github.com/oraios/serena/issues/478
- ast-grep repository: https://github.com/ast-grep/ast-grep
- ast-grep rewrite docs: https://ast-grep.github.io/guide/rewrite-code.html
- ast-grep YAML/config docs: https://ast-grep.github.io/reference/yaml.html
- ast-grep debugging docs: https://ast-grep.github.io/blog/how-to-debug.html
- Comby repository: https://github.com/comby-tools/comby
- Comby docs overview: https://comby.dev/docs/overview
- Comby syntax reference: https://comby.dev/docs/syntax-reference
- jscodeshift repository/docs: https://github.com/facebook/jscodeshift

Prior-art inputs reviewed:
- PR 501: https://github.com/stars-end/agent-skills/pull/501
- PR 492: https://github.com/stars-end/agent-skills/pull/492
- PR 490: https://github.com/stars-end/agent-skills/pull/490
