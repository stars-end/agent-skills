---
name: area-context-create
description: |
  Create repo-local codebase area context skills for rapid navigation (compatibility/legacy pattern).
  Use for repo-local area context skills only. Canonical skill work uses `agent-skills-creator`.
  Handles ONE-TIME auto-detection with Serena, template-based generation, and manual maintenance.
  Use when creating new area contexts or regenerating existing ones,
  or when user mentions "create context skill", "generate area context", "map codebase area",
  skill generation, codebase navigation, area mapping, or template-based skill creation.
tags: [meta, skill-creation, context, automation, compatibility]
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - mcp__serena__*
---

# Area Context Create (Repo-Local)

> ⚠️ **Compatibility/Legacy Pattern**: Creates repo-local `.claude/skills/context-*` skills.
> For canonical skill work in `~/agent-skills`, use `agent-skills-creator`.

Create repo-local context skills for codebase areas (<5 min per area, one-time setup).

## Purpose

Generate specialized context skills that help agents instantly navigate specific codebase areas (analytics, brokerage, security-resolver, core-data). Each area skill provides:

- **Quick file navigation** (15 min → instant lookup)
- **Symbol-level indexing** (classes, functions, key exports)
- **Backup file disambiguation** (active vs deprecated)
- **Test file coverage** (where to find tests)
- **Entry point guidance** (where to start reading)

**Impact:** Solves 15-minute navigation pain by pre-loading 4 area contexts (28KB total overhead in 200K context).

**Philosophy:** Manual maintenance (like docs-create), ONE-TIME auto-detection for initial creation.

## When to Use This Skill

**Trigger phrases:**
- "create analytics context"
- "set up brokerage area skill"
- "regenerate security-resolver context"
- "update core-data navigation"

**Use when:**
- Initial setup (creating all 4 area contexts)
- New area added (expand beyond 4 areas)
- Major refactor (file structure changed significantly)
- Manual maintenance (area expanded, files moved)

**Don't use when:**
- Minor file changes (wait for batch regeneration)
- PR-level updates (Phase 2 automation handles this)
- Exploring codebase (use Serena tools directly)

## Workflow

### 1. Read Area Configuration

Parse `.context/area-config.yml` to understand:
- Which area to create/update
- Glob patterns for file matching
- Detector patterns for content scoring
- Exclude patterns (backup files, deprecated)

```bash
# Read config
Read .context/area-config.yml

# Validate area exists
if area not in config.areas:
  echo "Error: Area '$area' not defined in area-config.yml"
  exit 1
```

### 2. Auto-Detect Files (ONE-TIME)

Use Serena to discover files matching area globs:

```python
# List files matching glob patterns
files = []
for glob_pattern in area_config.globs:
  matches = mcp__serena__list_dir(
    relative_path=extract_base_path(glob_pattern),
    recursive=True,
    file_extensions=extract_extensions(glob_pattern)
  )
  files.extend(filter_by_glob(matches, glob_pattern))

# Apply exclude patterns
files = [f for f in files if not matches_exclude(f, area_config.excludes)]

# Score files by relevance (detector patterns)
scored_files = []
for file in files:
  confidence = calculate_confidence(file, area_config.detectors)
  if confidence >= settings.auto_detect.confidence_threshold:
    scored_files.append((file, confidence))

# Sort by confidence (highest first)
scored_files.sort(key=lambda x: x[1], reverse=True)

# Cap at max_files_per_area
top_files = scored_files[:settings.skill.max_files_per_area]
```

**Confidence calculation:**
```python
def calculate_confidence(file_path, detectors):
  # Base score from glob match
  confidence = 0.5

  # Read file content (use Serena)
  content = Read(file_path)

  # Apply detector patterns
  for detector in detectors:
    if re.search(detector.pattern, content):
      confidence += detector.weight

  return min(confidence, 1.0)  # Cap at 1.0
```

### 3. Index Symbols with Serena

For each top file, extract symbol overview:

```python
indexed_files = []
for file_path, confidence in top_files:
  # Get symbols overview (lightweight, no bodies)
  overview = mcp__serena__get_symbols_overview(
    relative_path=file_path
  )

  # Parse key symbols
  symbols = {
    "classes": [s.name for s in overview.symbols if s.kind == "class"],
    "functions": [s.name for s in overview.symbols if s.kind == "function"],
    "exports": [s.name for s in overview.symbols if s.exported]
  }

  # Detect file status
  status = "active"
  if "backup" in file_path.lower() or "old" in file_path.lower():
    status = "deprecated"
  elif file_path.startswith("tests/"):
    status = "test"

  indexed_files.append({
    "path": file_path,
    "confidence": confidence,
    "symbols": symbols,
    "status": status,
    "loc": count_lines(file_path)
  })
```

### 4. Generate SKILL.md from Template

Use template substitution (like docs-create pattern):

```bash
# Read template
template_path=".claude/skills/area-context-create/resources/templates/area-context-template.md"
template_content=$(Read $template_path)

# Prepare metadata
area_name="$1"
description=$(yq .areas.$area_name.description .context/area-config.yml)
keywords=$(yq .areas.$area_name.keywords .context/area-config.yml || echo "")
tags=$(yq .areas.$area_name.tags .context/area-config.yml || echo "[codebase]")
total_files=$(echo "$indexed_files" | jq 'length')
total_loc=$(echo "$indexed_files" | jq '[.[] | .loc] | add')
created_date=$(date +%Y-%m-%d)

# Group files by status (active, deprecated, test)
active_files=$(echo "$indexed_files" | jq '[.[] | select(.status == "active")]')
deprecated_files=$(echo "$indexed_files" | jq '[.[] | select(.status == "deprecated")]')
test_files=$(echo "$indexed_files" | jq '[.[] | select(.status == "test")]')

# Generate file listings
active_listing=$(generate_file_listing "$active_files")
deprecated_listing=$(generate_file_listing "$deprecated_files")
test_listing=$(generate_file_listing "$test_files")

# Substitute placeholders
skill_content=$(echo "$template_content" | \
  sed "s/{{AREA_NAME}}/$area_name/g" | \
  sed "s/{{DESCRIPTION}}/$description/g" | \
  sed "s/{{KEYWORDS}}/$keywords/g" | \
  sed "s/{{TAGS}}/$tags/g" | \
  sed "s/{{TOTAL_FILES}}/$total_files/g" | \
  sed "s/{{TOTAL_LOC}}/$total_loc/g" | \
  sed "s/{{CREATED_DATE}}/$created_date/g" | \
  sed "s|{{ACTIVE_FILES}}|$active_listing|g" | \
  sed "s|{{DEPRECATED_FILES}}|$deprecated_listing|g" | \
  sed "s|{{TEST_FILES}}|$test_listing|g")

# Write to skill directory
skill_dir=".claude/skills/context-$area_name"
mkdir -p "$skill_dir"
echo "$skill_content" > "$skill_dir/SKILL.md"
```

**File listing format:**
```markdown
### Backend (Active)
- analytics_api.py:22 - `get_portfolio_summary()` ✅ CURRENT
- analytics_supabase.py:70 - `SupabaseAnalyticsEngine` class
- analytics_models.py:15 - `PortfolioMetrics` data model

### Backend (Deprecated)
- analytics_api_backup.py ❌ DO NOT EDIT (backup from 2024-11-10)

### Tests
- tests/analytics/test_api.py:50 - `test_portfolio_summary()`
```

**Template variables explained:**

| Variable | Source | Purpose | Example |
|----------|--------|---------|---------|
| `{{AREA_NAME}}` | CLI arg | Area identifier | `analytics` |
| `{{DESCRIPTION}}` | area-config.yml | Brief summary | `Portfolio analytics, metrics calculation` |
| `{{KEYWORDS}}` | area-config.yml | Trigger words for skill activation | `analytics, metrics, portfolio, dashboard` |
| `{{TAGS}}` | area-config.yml | Skill categorization | `[backend, analytics, data]` |
| `{{TOTAL_FILES}}` | Auto-detected | File count | `15` |
| `{{TOTAL_LOC}}` | Auto-calculated | Lines of code | `2847` |
| `{{CREATED_DATE}}` | Auto-generated | Timestamp | `2025-01-18` |
| `{{ACTIVE_FILES}}` | Auto-generated | Current file listing | See format above |
| `{{DEPRECATED_FILES}}` | Auto-generated | Deprecated file listing | See format above |
| `{{TEST_FILES}}` | Auto-generated | Test file listing | See format above |

**Note:** The enhanced description field now includes "Use when...", "Invoke when...", and "Keywords:" sections to improve Claude Code's skill activation detection. The {{KEYWORDS}} and {{TAGS}} variables should be defined in area-config.yml for each area.

### 5. Verify and Report

Final validation:

```bash
# Verify SKILL.md created
if [ ! -f ".claude/skills/context-$area_name/SKILL.md" ]; then
  echo "Error: Failed to create SKILL.md"
  exit 1
fi

# Report results
echo "✅ Area context created: context-$area_name"
echo "   Files indexed: $total_files"
echo "   Total LOC: $total_loc"
echo "   Active files: $(echo $active_files | jq 'length')"
echo "   Deprecated: $(echo $deprecated_files | jq 'length')"
echo "   Tests: $(echo $test_files | jq 'length')"
echo ""
echo "📁 Created: .claude/skills/context-$area_name/SKILL.md (repo-local)"
echo ""
echo "🔄 To update later:"
echo "   scripts/area-context-update $area_name"
```

> ⚠️ **Note**: Auto-activation via `skill-rules.json` is a legacy pattern. Modern skill activation relies on semantic description matching.

## Integration Points

### With Serena MCP

**Pattern:**
```python
# Don't use bash find/grep - use Serena
files = mcp__serena__list_dir(relative_path="backend", recursive=True)
overview = mcp__serena__get_symbols_overview(relative_path="backend/api/analytics_api.py")
```

**Benefits:**
- Respects .gitignore (no node_modules, .venv pollution)
- Symbol-aware (classes, functions, exports)
- Faster than bash find/grep

### With area-config.yml

**Pattern:**
```yaml
# Manual maintenance (user controls)
areas:
  analytics:
    globs:
      - "backend/**/*analytics*.py"  # User adds/removes patterns
      - "frontend/src/components/*Analytics*.tsx"
```

**When user updates config:**
```bash
# Regenerate area
scripts/area-context-update analytics
```

### With Scripts

**Pattern:**
```bash
# ONE-TIME auto-detect
scripts/area-context-create analytics

# Manual regeneration
scripts/area-context-update analytics

# Batch regenerate all areas
for area in $(yq '.areas | keys | .[]' .context/area-config.yml); do
  scripts/area-context-update "$area"
done
```

## Best Practices

### Do

✅ Use ONE-TIME auto-detection for initial creation only
✅ Rely on manual area-config.yml maintenance
✅ Mark backup files clearly (❌ DO NOT EDIT)
✅ Group files by status (active, deprecated, test)
✅ Cap at max_files_per_area (prevent context bloat)
✅ Sort by relevance (confidence scores)
✅ Include symbol-level navigation (classes, functions)
✅ Test the generated skill (try navigating with it)

### Don't

❌ Auto-update areas continuously (manual maintenance only)
❌ Include backup files in active listings
❌ Exceed 500 lines in main SKILL.md (use resources/)
❌ Skip confidence filtering (respect thresholds)
❌ Treat legacy `skill-rules.json` updates as required
❌ Create skills for areas with <5 files (too small)

## What This Skill Does

✅ Parse area-config.yml for area definition
✅ Auto-detect files using Serena (ONE-TIME)
✅ Score files by confidence (glob + detector patterns)
✅ Index symbols (classes, functions, exports)
✅ Identify file status (active, deprecated, test)
✅ Generate SKILL.md from template
✅ Report results (files, LOC, status breakdown)

## What This Skill DOESN'T Do

❌ Continuous auto-update (manual maintenance only)
❌ Deep dependency analysis (Serena doesn't support this)
❌ Automatic area discovery (user defines areas)
❌ GitHub Actions integration (Phase 2 handles this)
❌ PR-level incremental updates (use area-context-update)

## Examples

### Example 1: Create Analytics Context

```
User: "create analytics context"

AI reads .context/area-config.yml
→ Area: analytics
→ Globs: backend/**/*analytics*.py, frontend/**/*Analytics*.tsx
→ Detectors: SupabaseAnalyticsEngine, calculate_portfolio

AI uses Serena to list files
→ Found 23 files matching globs
→ Apply excludes (backup files removed)
→ Score by confidence (detector patterns)
→ Top 20 files (confidence > 0.5)

AI indexes symbols with Serena
→ analytics_api.py: get_portfolio_summary(), ...
→ analytics_supabase.py: SupabaseAnalyticsEngine class
→ analytics_models.py: PortfolioMetrics model

AI generates SKILL.md from template
→ Substitute {{AREA_NAME}} → analytics
→ Substitute {{ACTIVE_FILES}} → formatted listing
→ Write to .claude/skills/context-analytics/SKILL.md

Result:
✅ Created: context-analytics skill
✅ Files: 20 active, 2 deprecated, 5 tests
✅ Total LOC: 3,200
✅ Navigation: 15 min → instant
```

### Example 2: Regenerate After Major Refactor

```
User: "regenerate all area contexts"

AI batch regenerates:
for area in [analytics, brokerage, security-resolver, core-data]:
  scripts/area-context-update $area

analytics: ✅ Updated (5 new files, 2 removed)
brokerage: ✅ Updated (no changes)
security-resolver: ✅ Updated (3 files moved)
core-data: ✅ Updated (10 new migrations)

Result:
✅ All 4 areas refreshed
✅ Total time: 8 minutes
✅ Ready for navigation
```

### Example 3: Add New Area (Future)

```
User: "add reporting area"

AI guides user:
1. Edit .context/area-config.yml
2. Add reporting area definition:
   areas:
     reporting:
       description: "Report generation, exports, PDFs"
       globs: ["backend/**/*report*.py", "frontend/**/*Report*.tsx"]
3. Run: scripts/area-context-create reporting

Result:
✅ Created: context-reporting skill
✅ 5th area added to system
✅ Pre-loaded in all sessions (34KB total overhead)
```

## Troubleshooting

### No Files Found

**Symptom:** Auto-detect finds 0 files for area

**Diagnosis:**
- Check glob patterns in area-config.yml
- Verify files exist (use bash ls or Serena list_dir)
- Check exclude patterns (might be too broad)

**Fix:**
```bash
# Debug glob matching
yq '.areas.analytics.globs' .context/area-config.yml
ls backend/**/*analytics*.py
```

### Low Confidence Scores

**Symptom:** All files filtered out by confidence threshold

**Diagnosis:**
- Detector patterns don't match file contents
- Threshold too high (default 0.5)

**Fix:**
```yaml
# Lower threshold in area-config.yml
settings:
  auto_detect:
    confidence_threshold: 0.3  # Was 0.5
```

### Too Many Files

**Symptom:** Area has >50 files (exceeds max_files_per_area)

**Diagnosis:**
- Globs too broad (matching unrelated files)
- Area too large (consider splitting)

**Fix:**
```yaml
# Narrow globs
globs:
  - "backend/api/*analytics*.py"  # More specific
  # - "backend/**/*analytics*.py"  # Too broad (removed)

# Or increase cap
settings:
  skill:
    max_files_per_area: 80  # Was 50
```

## Related Resources

- **Template:** resources/templates/area-context-template.md (SKILL.md generation)
- **Examples:** resources/examples/ (sample generated skills)
- **Scripts:** scripts/area-context-create, scripts/area-context-update
- **Config:** .context/area-config.yml (area definitions)

---

**Last Updated:** 2026-03-08
**Skill Type:** Meta-skill (compatibility/legacy)
**Impact:** Repo-local context skills (`.claude/skills/context-*`)
**Average Duration:** 5 minutes per area
**Related Docs:**
- AGENTS.md (Issue-First core principle)
- `~/agent-skills/extended/agent-skills-creator/SKILL.md` (canonical skill creation)
