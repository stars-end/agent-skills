# Agent Skills

Global DX skills shared across all VMs and projects.

## Structure
- Each skill in its own directory with `SKILL.md`
- Synced via git to `github.com/stars-end/agent-skills`

## Updating Skills
1. Edit skill in this directory
2. Commit and push
3. Other VMs auto-pull on shell start (or manually `git pull`)

## Skill Categories
- Beads integration (beads-workflow, beads-guard, issue-first, etc.)
- PR automation (create-pull-request, fix-pr-feedback, etc.)
- Development tooling (skill-creator, lint-check, etc.)
- DevOps (devops-dx)

# test-1769214938
=== Test 1: Dirty repo checkpoint === cd /home/feng/agent-skills echo # test-$(date +%s) /home/feng/.local/bin/auto-checkpoint.sh /home/feng/agent-skills
# test-1769215020
=== Test 2: Clean repo handling === /home/feng/.local/bin/auto-checkpoint.sh /home/feng/agent-skills exit_code= echo Exit code:  (0=success, 1=clean) echo  echo === Test 3: GLM fallback === mv /home/feng/.config/secret-cache/secrets.env /home/feng/.config/secret-cache/secrets.env.bak echo # test /home/feng/.local/bin/auto-checkpoint.sh /home/feng/agent-skills
