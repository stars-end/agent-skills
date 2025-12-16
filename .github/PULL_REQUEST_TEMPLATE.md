# Pull Request: [Feature Name]

## Summary

Brief description of what this PR does.

## Changes

- [ ] New composite actions
- [ ] Workflow templates
- [ ] Skills updated
- [ ] Documentation

## Agent Update Required?

**🚨 CRITICAL: If this PR requires agents to take action, you MUST update AGENT_UPDATE_INSTRUCTIONS.md**

- [ ] **YES** - Agents need to update/deploy something
  - [ ] ✅ Updated `AGENT_UPDATE_INSTRUCTIONS.md` with:
    - [ ] Copy-paste instructions for all agents
    - [ ] Step-by-step deployment per VM
    - [ ] Verification steps
    - [ ] Troubleshooting guide
    - [ ] Rollout status checklist
  - [ ] ✅ Updated `LATEST_UPDATE.md` with quick start
  - [ ] ✅ Included deployment examples in PR description

- [ ] **NO** - Internal refactor/docs only, no agent action needed

## Testing

- [ ] Tested locally
- [ ] Verified on test repo
- [ ] Documented testing steps in AGENT_UPDATE_INSTRUCTIONS.md (if applicable)

## Deployment

### If Agent Update Required:

**Copy-paste this to all agents after merge**:
```
🔔 AGENT-SKILLS UPDATE AVAILABLE

Feature: [Feature Name]
Action Required: [Yes/No]
Time: [X minutes]

Instructions: cat ~/.agent/skills/AGENT_UPDATE_INSTRUCTIONS.md
Or: https://github.com/stars-end/agent-skills/blob/main/AGENT_UPDATE_INSTRUCTIONS.md
```

### Deployment Steps (from AGENT_UPDATE_INSTRUCTIONS.md):
```bash
# Paste deployment steps here
```

## Checklist

- [ ] All changed files committed
- [ ] AGENT_UPDATE_INSTRUCTIONS.md updated (if required)
- [ ] LATEST_UPDATE.md updated
- [ ] README(s) updated for new components
- [ ] Tested in isolation
- [ ] Copy-paste distribution message prepared (above)
- [ ] Beads issue linked: bd-XXXX

## Related

- Beads issue: bd-XXXX
- Related PRs: #XXX
- Dependent repos: (list repos that need to deploy this)
