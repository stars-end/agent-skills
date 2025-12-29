# DX Troubleshooting Guide

**Tags:** #git #troubleshooting #errors #dx

## 1. "Dirty Repo" / Local Changes Blocking Pull
**Symptom:** You try to run `git pull` (or a hydration script) and it fails because of "local changes" or "untracked files".
**Protocol:**
Do NOT stop. Safely stash and update.

```bash
# 1. Save local work
git stash save "Auto-save before sync $(date)"

# 2. Update
git pull origin master --rebase

# 3. Restore work
git stash pop || echo "⚠️ Conflict on pop - resolve manually"
```

## 2. "Binary Missing" (cass / universal-skills)
**Symptom:** `dx-status.sh` reports missing binaries.
**Protocol:**

**universal-skills:**
```bash
npm install -g universal-skills
```

**cass:**
```bash
# Clone the toolbox if missing
if [ ! -d ~/knowledge_and_vibes ]; then
  git clone https://github.com/Mburdo/knowledge_and_vibes.git ~/knowledge_and_vibes
fi
# Link
ln -sf ~/knowledge_and_vibes/tools/cass ~/bin/cass
```

## 3. "Hook Failed" / Missing Script
**Symptom:** `git commit` fails with `python3: can't open file '.../validate_beads.py': [Errno 2] No such file`.
**Cause:** The `pre-commit` hook is installed, but the script it points to hasn't been pulled yet.
**Fix:**
```bash
cd ~/agent-skills
git pull origin master
```
