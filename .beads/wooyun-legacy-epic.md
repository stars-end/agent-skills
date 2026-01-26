---
epic: true
priority: P2
---

# Integrate WooYun Legacy Security Skill into agent-skills

## Overview
Integrate [wooyun-legacy](https://github.com/tanweai/wooyun-legacy) (88,636 real vulnerability cases) into `~/agent-skills/` as a canonical security skill.

## Value Proposition
- **Security expertise**: Provides AI agents with deep knowledge of 15 vulnerability types
- **No existing security skill**: First dedicated security skill in agent-skills
- **Battle-tested knowledge**: Based on real-world exploitation patterns from 2010-2016
- **Multiple use cases**: Code security audits, penetration testing guidance, vulnerability detection, secure coding practices

## Scope
- Clone and adapt wooyun-legacy to agent-skills conventions
- Ensure compatibility with skills plane architecture
- Document usage patterns and integration points
- Test with Claude Code and potentially other agent tools

## Out of Scope
- Updating the vulnerability knowledge base (upstream maintenance)
- Creating new vulnerability detection tools
- Integrating with specific CI/CD pipelines (future enhancement)

---

## Subtasks

### 1. Clone wooyun-legacy into agent-skills
- Clone https://github.com/tanweai/wooyun-legacy.git to `~/agent-skills/wooyun-legacy/`
- Verify directory structure matches expectations (SKILL.md, knowledge/, categories/)
- Remove upstream-specific files (wechat-group.jpg, community links)
- Commit initial clone with descriptive message

### 2. Adapt SKILL.md to agent-skills conventions
- Add frontmatter section with:
  - `name`: security-vuln-analysis (or wooyun-legacy)
  - `description`: Security vulnerability analysis based on 88,636 real cases
  - `tags`: [security, vuln, audit, penetration]
  - `allowed-tools`: Read, Grep, Bash, WebFetch (existing tools from skill)
- Ensure SKILL.md follows SKILLS_PLANE.md conventions:
  - Clear usage examples
  - When to use / when NOT to use
  - Exit codes (if applicable)
  - Integration with other skills
  - Troubleshooting section
- Add disclaimer about security research/authorized testing only

### 3. Adapt to shared core conventions
- Add `profile.json` for environment-specific behavior (default vs strict vs ci)
  - Default: Warn-only, educational guidance
  - Strict: Fail on critical vulnerability findings
  - CI: Strict mode, report only high-severity issues
- Ensure no secrets in output (already in upstream, verify)
- Add color output helpers from SKILLS_PLANE.md core utilities (if scripts added)
- Document idempotent operations (skill invocation should be safe to repeat)

### 4. Create helper scripts (optional but recommended)
- `scripts/security-audit.sh`: Wrapper for code security auditing
  - Accepts: target directory or file
  - Outputs: Vulnerability findings with severity ratings
  - Uses: SKILL.md knowledge + grep/analysis patterns
- `scripts/vuln-scan.sh`: Quick vulnerability pattern scan
  - Accepts: repository root
  - Outputs: List of potential vulnerability patterns found
  - Uses: knowledge/ patterns for SQL injection, XSS, command execution, etc.
- Ensure scripts follow shared core conventions (exit codes, no secrets, warn-only locally)

### 5. Create integration documentation
- Add `docs/SECURITY_SKILLS.md` documenting:
  - Overview of security skills (wooyun-legacy currently only one)
  - When to invoke security skill (pre-commit, code review, security audits)
  - Integration with other agent-skills workflows
  - Example usage patterns
- Update `README.md` to mention security skills section
- Add cross-references from relevant skills (e.g., git-safety-guard, dcg-safety)

### 6. Test skill functionality
- Test skill invocation via Claude Code (or available agent tool)
- Verify SKILL.md loads correctly
- Test helper scripts (if implemented):
  - Run `~/agent-skills/wooyun-legacy/scripts/security-audit.sh` on test code
  - Run `~/agent-skills/wooyun-legacy/scripts/vuln-scan.sh` on test repo
- Verify knowledge base files are accessible (knowledge/, categories/)
- Test profile switching (default vs strict vs ci)

### 7. Validate skills plane integration
- Verify skill is discoverable via `~/.agent/skills/` mount point
- Test skill works with agent-skills shared core conventions
- Verify no conflicts with existing skills
- Check that skill doesn't break agent-skills CI (if any)

### 8. Create PR and documentation updates
- Open PR to `stars-end/agent-skills` with:
  - Complete wooyun-legacy integration
  - All subtasks completed
  - Clear commit history
- Update `CONTRIBUTING.md` if needed (security skill section)
- Add to `SKILLS_PLANE.md` if security skills deserve dedicated section
- Create changelog entry

---

## Dependencies
- None (independent epic)

## Related Issues
- None (new capability)

## Acceptance Criteria
- [ ] wooyun-legacy cloned to `~/agent-skills/wooyun-legacy/`
- [ ] SKILL.md follows agent-skills conventions (frontmatter, structure, examples)
- [ ] Helper scripts implement security auditing/vulnerability scanning (optional but recommended)
- [ ] Documentation updated (SECURITY_SKILLS.md, README.md, SKILLS_PLANE.md)
- [ ] Skill tested and functional (Claude Code or other agent tool)
- [ ] Skills plane integration validated
- [ ] PR opened with complete implementation

## Notes
- Upstream repo: https://github.com/tanweai/wooyun-legacy
- License: Verify license before integration (check upstream)
- Size: 86MB knowledge base - consider if this should be in .gitignore or partially excluded
- Chinese language content: Consider translating key sections to English or keep bilingual
- Upstream maintenance: Note that this skill may not be actively maintained; security knowledge could be dated (2010-2016)
