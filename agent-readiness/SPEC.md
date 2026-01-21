# Agent Readiness Framework

## Overview

A framework for measuring and improving how well codebases support autonomous development. Inspired by Factory.ai's Agent Readiness.

## Eight Technical Pillars

1. **Style & Validation** - Linters, type checkers, formatters (ESLint, Biome, TypeScript strict mode, Prettier, Black)
2. **Build System** - Reproducible builds, dependency management, build scripts
3. **Testing** - Unit tests, integration tests, E2E tests, test coverage
4. **Documentation** - README, AGENTS.md, API docs, onboarding guides
5. **Dev Environment** - Docker, Vagrant, nix, reproducible local setup
6. **Code Quality** - Code reviews, CI checks, automated quality gates
7. **Observability** - Logging, metrics, tracing, error tracking
8. **Security & Governance** - Security scanning, dependency audits, branch protection, CODEOWNERS

## Five Maturity Levels

| Level | Name | Description | Agent Capability |
|-------|------|-------------|------------------|
| 1 | Functional | Basic code works | None meaningful |
| 2 | Documented | Docs exist, basic processes | Read-only understanding |
| 3 | Standardized | Production-ready for agents | Routine maintenance: bug fixes, tests, docs, dependency upgrades |
| 4 | Optimized | Fast feedback, automated | Complex refactoring, feature work |
| 5 | Autonomous | Self-healing, adaptive | Full autonomous development |

**Level 3 is the target** - minimum bar for production-grade autonomous operation.

## Scoring Mechanism

- Binary pass/fail for 60+ criteria
- Unlock a level by passing **80%** of criteria from that level AND all previous levels
- Gated progression emphasizes building on solid foundations
- Organization-level metric: percentage of active repos at Level 3+

## Evaluation Scopes

- **Repository-scoped**: Run once per repo (CODEOWNERS, branch protection)
- **Application-scoped**: Run per app in monorepos (linter config per app, tests per app)
- Monorepo scores shown as "3/4 apps pass this criterion"

## CLI Tool: `/readiness-report`

Evaluates any repository and displays:
- Current maturity level
- Pass/fail criteria by pillar
- Prioritized remediation suggestions

Supports local and remote repo evaluation.

## LLM Grounding for Consistency

To minimize variance (target < 1%):
- Ground each evaluation on the previous report for that repository
- Use previous report as context for new evaluations
- Benchmark across repos spanning low/medium/high readiness tiers

## Automated Remediation

Spin up an agent to open PRs for failing criteria:
- Add missing documentation (AGENTS.md)
- Configure linters and formatters
- Set up pre-commit hooks
- Fix foundational gaps first (high-impact, straightforward)

## API Interface

Programmatic access for:
- CI/CD integration
- Custom dashboards
- Alerting when scores drop below thresholds
- Repo filtering and pagination

## Beads Epic

Epic: `agent-skills-dzb` - Agent Readiness: Framework for evaluating codebase readiness for autonomous development

### Child Tasks

| Beads ID | Task | Priority |
|----------|------|----------|
| agent-skills-dzb.1 | Research and spec Agent Readiness framework | P0 |
| agent-skills-dzb.2 | Implement core evaluation framework | P1 |
| agent-skills-dzb.3 | Implement 5-level maturity scoring | P1 |
| agent-skills-dzb.4 | Implement LLM evaluation with grounding | P1 |
| agent-skills-dzb.5 | Implement CLI tool: /readiness-report | P1 |
| agent-skills-dzb.6 | Implement automated remediation | P2 |
| agent-skills-dzb.7 | Implement API for programmatic access | P2 |
| agent-skills-dzb.8 | Testing and documentation | P1 |

## References

- Factory.ai Agent Readiness: https://factory.ai/news/agent-readiness
- Readiness Reports API: https://docs.factory.ai/reference/readiness-reports-api
