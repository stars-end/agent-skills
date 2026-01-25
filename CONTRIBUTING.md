# Contributing to Agent-Skills

**Repository Purpose**: Shared skills, GitHub Actions, and workflows for AI agents across all projects.

---

## 📋 DX Bootstrap Contract

**All agents working across repos MUST follow the [DX Bootstrap Contract](./DX_BOOTSTRAP_CONTRACT.md)**

### Quick Reference

**Session start sequence** (mandatory):
1. `git pull origin master`
2. `dx-check`
3. Optional (only if using coordinator services): `DX_BOOTSTRAP_COORDINATOR=1 dx-doctor`

**See**: `DX_BOOTSTRAP_CONTRACT.md` for full details

---

## 🚨 Critical Rule: Agent Update Instructions

**EVERY PR that requires agents to take action MUST update `AGENT_UPDATE_INSTRUCTIONS.md`**

### When is Agent Update Required?

**YES - Update Required:**
- ✅ New composite actions (agents must reference new action)
- ✅ New workflow templates (agents must copy to repos)
- ✅ New skills (agents must pull latest)
- ✅ Skill behavior changes (affects workflow)
- ✅ Breaking changes to existing components
- ✅ New dependencies or setup steps

**NO - Update Not Required:**
- ❌ Internal refactoring (no behavior change)
- ❌ Documentation fixes (typos, clarifications)
- ❌ README updates (no action needed)
- ❌ Test additions (no agent workflow impact)

### Required Documentation

For EVERY agent-update PR, update **BOTH**:

1. **`AGENT_UPDATE_INSTRUCTIONS.md`** - Comprehensive guide
   - Copy-paste instructions for all agents
   - Step-by-step deployment per VM
   - Verification steps and testing
   - Troubleshooting guide
   - Rollout status checklist

2. **`LATEST_UPDATE.md`** - Quick reference
   - Add new feature at top
   - Quick start (1-5 minute version)
   - Link to full instructions

### Template for AGENT_UPDATE_INSTRUCTIONS.md

```markdown
# Agent Update Instructions: [Feature Name] (bd-XXXX)

**Date**: YYYY-MM-DD
**Version**: X.X.X
**Affects**: [All agents / Specific repos]

---

## 📋 Copy-Paste This To All Agents

\`\`\`
🔔 AGENT-SKILLS UPDATE AVAILABLE
Feature: [Feature Name]
Action Required: [What needs to be done]
Time: [X minutes]
Instructions: cat ~/.agent/skills/AGENT_UPDATE_INSTRUCTIONS.md
\`\`\`

---

## 🎯 What This Update Does
...

## 🚀 Quick Start (All Agents)
...

## 🔄 Updated Workflow (What Changed)
...

## 📝 Agent-Specific Actions
...

## 🧪 Testing Instructions
...

## ❓ FAQ
...

## 🐛 Troubleshooting
...

## 📊 Rollout Status Tracking
...
```

---

## 📁 Repository Structure

```
agent-skills/
├── github-actions/
│   ├── actions/          # Composite actions (reusable logic)
│   │   └── */action.yml
│   └── workflows/        # Workflow templates (copy-on-deploy)
│       └── *.yml.ref
├── skills/               # Global skills (behavior + instructions)
│   └── */SKILL.md
├── serena-patterns/      # Serena MCP usage patterns
├── AGENT_UPDATE_INSTRUCTIONS.md  # 🚨 MUST UPDATE FOR AGENT CHANGES
├── LATEST_UPDATE.md               # Quick reference
└── CONTRIBUTING.md                # This file
```

---

## 🔄 Development Workflow

### 1. Create Beads Issue

```bash
bd create "[Feature Name]" --type feature --priority 1 --assignee claude-code
# Returns: bd-XXXX
```

### 2. Create Feature Branch

```bash
git checkout -b feature-bd-XXXX
```

### 3. Implement Changes

**Follow patterns**:
- **Composite actions**: 80% logic, reusable across repos
- **Workflow templates**: 20% orchestration, copy-on-deploy
- **Skills**: Autonomous agent behavior + clear instructions

### 4. Update Documentation

**Required updates**:
- [ ] Component README (actions/*/README.md, skills/*/SKILL.md)
- [ ] AGENT_UPDATE_INSTRUCTIONS.md (if agent action needed)
- [ ] LATEST_UPDATE.md (add to top)
- [ ] Repository README (if new category)

### 5. Create PR

**Use PR template** (auto-populated):
- Summary and changes
- **Agent Update Required?** checkbox (critical!)
- Testing steps
- Deployment instructions
- Copy-paste distribution message

### 6. After Merge

**Distribute to all agents**:
```bash
# Post in team chat / send to other agents:
🔔 AGENT-SKILLS UPDATE AVAILABLE

Feature: [Feature Name]
Time: [X minutes]

All agents run:
  cd ~/.agent/skills && git pull
  cat AGENT_UPDATE_INSTRUCTIONS.md
```

---

## 🎯 Component-Specific Guidelines

### GitHub Actions Composite Actions

**Location**: `github-actions/actions/[action-name]/`

**Structure**:
```
action-name/
├── action.yml       # Composite action definition
└── README.md        # Usage, inputs, outputs, examples
```

**Requirements**:
- Clear inputs/outputs documentation
- Examples in README
- Safety checks (fail gracefully)
- Works across repos (no hardcoded paths)

**Template**:
See `github-actions/actions/auto-merge-beads/` for reference.

### Workflow Templates

**Location**: `github-actions/workflows/[workflow-name].yml.ref`

**Naming**: Always end with `.yml.ref` (signals copy-on-deploy)

**Requirements**:
- Use composite actions for logic (80/20 split)
- Document deployment steps in README
- Include in workflows/README.md table

**Deployment**:
```bash
cp ~/.agent/skills/github-actions/workflows/[workflow].yml.ref \
   ~/target-repo/.github/workflows/[workflow].yml
```

### Global Skills

**Location**: `skills/[skill-name]/SKILL.md` or `[skill-name]/SKILL.md`

**Requirements**:
- Autonomous behavior (no user input during execution)
- Clear step-by-step instructions
- Examples and edge cases
- Failure handling

**Template**:
See `create-pull-request/SKILL.md` for reference.

### Serena Patterns

**Location**: `serena-patterns/[pattern-name].md`

**Requirements**:
- Ready-to-use examples
- Explanation of when to use
- Common variations
- Performance notes

---

## ✅ PR Checklist

Before submitting PR, verify:

### Code Quality
- [ ] No hardcoded paths (use parameters/inputs)
- [ ] Safety checks included (fail gracefully)
- [ ] Tested in isolation
- [ ] Works across repos (if applicable)

### Documentation
- [ ] Component README complete
- [ ] AGENT_UPDATE_INSTRUCTIONS.md updated (if required)
- [ ] LATEST_UPDATE.md updated (add to top)
- [ ] PR description includes deployment steps
- [ ] Copy-paste distribution message prepared

### Testing
- [ ] Tested locally
- [ ] Tested in test repo (if applicable)
- [ ] Verification steps documented
- [ ] Troubleshooting guide included

### Beads Integration
- [ ] Beads issue linked in PR
- [ ] Commits have Feature-Key trailer
- [ ] Issue closed when PR merged (if feature/task)

---

## 🚀 Distribution Process

### After PR Merges

1. **Notify all agents** (team chat / async):
   ```
   🔔 AGENT-SKILLS UPDATE AVAILABLE

   Feature: [Feature Name]
   Action Required: [Yes/No]
   Time: [X minutes]

   All agents run:
     cd ~/.agent/skills && git pull
     cat AGENT_UPDATE_INSTRUCTIONS.md
   ```

2. **Track rollout** (use checklist in AGENT_UPDATE_INSTRUCTIONS.md):
   - [ ] VM1: agent-skills updated
   - [ ] VM2: agent-skills updated
   - [ ] VM3: agent-skills updated
   - [ ] VM4: agent-skills updated

3. **Verify deployment** (if workflows deployed):
   ```bash
   # Check in target repos
   ls -la .github/workflows/[new-workflow].yml
   ```

---

## 🐛 Troubleshooting

### "Agents didn't see my update"

**Check**:
- Did you update AGENT_UPDATE_INSTRUCTIONS.md?
- Did you send distribution message to all agents?
- Did agents run `git pull` in ~/.agent/skills?

**Fix**: Re-send distribution message with clear action items.

### "Agent took action but it didn't work"

**Check**:
- Are deployment steps in AGENT_UPDATE_INSTRUCTIONS.md correct?
- Did you test the deployment steps yourself?
- Is troubleshooting guide complete?

**Fix**: Update AGENT_UPDATE_INSTRUCTIONS.md with corrected steps and redistribute.

---

## 📞 Questions?

- **Beads issues**: Create issue in project using agent-skills
- **Urgent**: Tag @prime-radiant-ai team in chat
- **Documentation**: Check AGENT_UPDATE_INSTRUCTIONS.md and LATEST_UPDATE.md

---

**Last Updated**: 2025-12-08
**Maintained by**: Prime Radiant AI agents
