# 2026-04-10 Cloud Analysis Alternatives Research Contract

## Objective
Research cloud or cloud-backed alternatives to `llm-tldr` for the analysis / retrieval / discovery layer.

This contract exists because earlier memo waves under-covered hosted and managed code-intelligence systems. We want a focused answer on whether any cloud option meaningfully competes with `llm-tldr` on analysis-layer capability and whether any of them fit our operational constraints.

## In Scope
Analysis / retrieval / discovery only.

Required candidates:
- GitHub Copilot repository indexing / semantic code search
- Augment Context Engine
- Sourcegraph / Cody / Code Graph
- Greptile
- Harness AI semantic code search
- GitLab codebase semantic indexing / Duo-side context systems

Optional additions if credible:
- any other serious hosted code-intelligence product aimed at coding agents

## Out of Scope
- editing tools
- memory tooling
- migration implementation

## Core Questions
1. Which cloud options are real analysis-layer competitors versus just managed semantic search?
2. Which provide semantic discovery only, and which provide deeper structural tracing or impact-style analysis?
3. Which are usable by coding agents programmatically, versus being mostly IDE/chat surfaces?
4. What are the real privacy, IP egress, and operator-burden tradeoffs?
5. Does any cloud option justify replacing or augmenting `llm-tldr`?

## Required Evaluation Criteria
For each candidate, score:
- semantic discovery: `full` / `partial` / `none`
- exact structural tracing: `full` / `partial` / `none`
- call graph / impact: `full` / `partial` / `none`
- architecture understanding: `full` / `partial` / `none`
- agent usability / API surface: `full` / `partial` / `none`
- privacy / IP egress risk: `low` / `medium` / `high`
- operational burden: `low` / `medium` / `high`
- cloud dependency risk: `low` / `medium` / `high`

## Decision Standard
A cloud candidate should not be treated as an `llm-tldr` replacement unless it shows a compelling advantage on analysis quality, not just a nicer hosted semantic-search UX.

If a product is mostly:
- repo indexing
- semantic search
- IDE/chat augmentation
and lacks strong structural or impact analysis, say so plainly.

## Required Deliverable Shape
The delegate should produce a memo that includes:
1. candidate longlist
2. comparison matrix
3. explicit distinction between semantic search and structural/impact analysis
4. best theoretical capability vs best operational fit
5. explicit recommendation among:
- keep local-first (`llm-tldr`)
- augment with cloud option(s)
- replace with cloud option
- no worthwhile cloud alternative found
