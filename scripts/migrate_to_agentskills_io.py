#!/usr/bin/env python3
"""
migrate_to_agentskills_io.py - Migrate SKILL.md files to agentskills.io format

Adds YAML frontmatter with name and description to all SKILL.md files.
"""

import os
import re
from pathlib import Path

SKILLS_ROOT = Path.home() / "agent-skills"

def extract_description(content: str) -> str:
    """Extract first meaningful paragraph as description."""
    lines = content.split('\n')
    desc_lines = []
    
    for line in lines:
        # Skip empty lines and headers at start
        if not line.strip():
            if desc_lines:
                break
            continue
        if line.startswith('#'):
            continue
        # Found content line
        desc_lines.append(line.strip())
        if len(' '.join(desc_lines)) > 100:
            break
    
    desc = ' '.join(desc_lines)
    # Truncate to 200 chars
    if len(desc) > 200:
        desc = desc[:197] + "..."
    return desc or "Agent skill for automated workflows."

def has_frontmatter(content: str) -> bool:
    """Check if file already has YAML frontmatter."""
    return content.strip().startswith('---')

def add_frontmatter(skill_path: Path) -> bool:
    """Add agentskills.io frontmatter to SKILL.md file."""
    skill_name = skill_path.parent.name
    
    # Validate skill name format
    if not re.match(r'^[a-z][a-z0-9-]*[a-z0-9]$', skill_name) and len(skill_name) > 1:
        print(f"  WARN: Name '{skill_name}' may not comply with agentskills.io spec")
    
    with open(skill_path, 'r') as f:
        content = f.read()
    
    if has_frontmatter(content):
        print(f"  SKIP: {skill_name} (already has frontmatter)")
        return False
    
    description = extract_description(content)
    
    frontmatter = f"""---
name: {skill_name}
description: {description}
---

"""
    
    with open(skill_path, 'w') as f:
        f.write(frontmatter + content)
    
    print(f"  ✅ Migrated: {skill_name}")
    return True

def main():
    print("=== Migrating to agentskills.io format ===\n")
    
    # Find all SKILL.md files
    skill_files = list(SKILLS_ROOT.glob("*/SKILL.md"))
    
    migrated = 0
    skipped = 0
    
    for skill_path in sorted(skill_files):
        if add_frontmatter(skill_path):
            migrated += 1
        else:
            skipped += 1
    
    print(f"\n=== Summary ===")
    print(f"Migrated: {migrated}")
    print(f"Skipped: {skipped}")
    print(f"Total: {migrated + skipped}")

if __name__ == "__main__":
    main()
