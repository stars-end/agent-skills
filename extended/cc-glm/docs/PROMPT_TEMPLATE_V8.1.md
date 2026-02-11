# cc-glm Prompt Template V8.1 (DX V8.1 Contract)

**Purpose:** Strict prompt compiler for cc-glm delegation. Ensures low-variance output from junior/mid delegates.

**Version:** 8.1.0
**Last Updated:** 2026-02-11

---

## Template Specification

### Required Fields (ALL mandatory)

```text
Beads: <beads-id>
Repo: <repo-name>
Worktree: /tmp/agents/<beads-id>/<repo-name>
Agent: cc-glm-headless

Hard constraints:
- Work ONLY in the worktree path above (never touch canonical clones under ~/{agent-skills,prime-radiant-ai,affordabot,llm-common})
- Do NOT run git commit, git push, or open PRs
- Do NOT print secrets, dotfiles, or config files
- Output must be reviewable: diff + validation + risks

Scope:
- In-scope: <concrete file paths or patterns>
- Out-of-scope: <explicit non-goals>
- Acceptance: <measurable criteria>

Task:
- <1-5 bullets of exact changes>

Expected outputs:
- Files changed: <list>
- Diff: <unified diff or patch>
- Validation: <commands run + results>
- Risks: <edge cases, gaps, follow-ups>
```

### Optional Fields (wave-based delegation)

```text
wave_id: <wave-identifier>
depends_on: <comma-separated list of beads-ids>
wave_order: <position in wave, 1-indexed>
```

**When to use wave fields:**
- `wave_id`: When batching multiple dependent tasks
- `depends_on`: When this task requires output from another delegated task
- `wave_order`: When tasks have sequential constraints within a wave

---

## Template Validation Rules

### 1. Header Validation

All prompts MUST include:
- `Beads:` - Beads issue ID (e.g., `bd-3p27.2`)
- `Repo:` - Repository name (e.g., `agent-skills`, `prime-radiant-ai`)
- `Worktree:` - Full worktree path (must be under `/tmp/agents/`)
- `Agent:` - Must be `cc-glm-headless` or `cc-glm`

### 2. Hard Constraints Validation

All prompts MUST include at least these constraints:
- Worktree-only constraint (no canonical writes)
- No commit/push/PR constraint
- No secrets/dotfiles constraint
- Output format requirement

### 3. Scope Validation

All prompts MUST define:
- **In-scope:** Specific files, directories, or patterns
- **Out-of-scope:** Explicit non-goals (what NOT to touch)
- **Acceptance:** Measurable completion criteria

### 4. Task Validation

Task description MUST be:
- Concrete (not "improve X", but "add Y to X")
- Bounded (1-5 bullets max)
- Atomic (single logical change)

### 5. Output Validation

Required output sections:
- `Files changed:` - List of modified files
- `Diff:` - Unified diff content
- `Validation:` - Commands run with pass/fail
- `Risks:` - Edge cases or unknowns

---

## Dependency Management

### Wave-Based Delegation Pattern

```bash
# Wave 1: Independent tasks
# Task A (no dependencies)
depends_on: [none]

# Task B (no dependencies)
depends_on: [none]

# Wave 2: Depends on Wave 1
# Task C (depends on A)
depends_on: [bd-aaa]
wave_id: wave-2
wave_order: 1

# Task D (depends on A and B)
depends_on: [bd-aaa, bd-bbb]
wave_id: wave-2
wave_order: 2
```

### Execution Order

1. **Wave 1:** Launch all tasks with `depends_on: [none]` in parallel (up to 4 workers)
2. **Wait:** Monitor all Wave 1 jobs via `cc-glm-job.sh status`
3. **Validate:** Review diffs and validation output from Wave 1
4. **Wave 2:** Launch tasks with satisfied dependencies
5. **Repeat:** Until all waves complete

---

## Example Generated Prompts

### Example 1: Simple Independent Task

```text
Beads: bd-3p27.2
Repo: agent-skills
Worktree: /tmp/agents/bd-3p27.2/agent-skills
Agent: cc-glm-headless

Hard constraints:
- Work ONLY in the worktree path above (never touch canonical clones under ~/{agent-skills,prime-radiant-ai,affordabot,llm-common})
- Do NOT run git commit, git push, or open PRs
- Do NOT print secrets, dotfiles, or config files
- Output must be reviewable: diff + validation + risks

Scope:
- In-scope: extended/cc-glm/docs/PROMPT_TEMPLATE_V8.1.md only
- Out-of-scope: No changes to scripts, SKILL.md, or other docs
- Acceptance: Template document exists with all required sections defined

Task:
- Add strict prompt template specification under extended/cc-glm/docs/
- Include required fields: Beads, Repo, Worktree, Agent, constraints
- Include optional wave fields: wave_id, depends_on, wave_order
- Include validation rules for template compliance
- Include example generated prompt

Expected outputs:
- Files changed: extended/cc-glm/docs/PROMPT_TEMPLATE_V8.1.md
- Diff: Full content of new file
- Validation: bash -n extended/cc-glm/scripts/*.sh passes
- Risks: None (documentation-only change)
```

### Example 2: Task with Dependencies (Wave 2)

```text
Beads: bd-3p28.1
Repo: agent-skills
Worktree: /tmp/agents/bd-3p28.1/agent-skills
Agent: cc-glm-headless

Hard constraints:
- Work ONLY in the worktree path above (never touch canonical clones under ~/{agent-skills,prime-radiant-ai,affordabot,llm-common})
- Do NOT run git commit, git push, or open PRs
- Do NOT print secrets, dotfiles, or config files
- Output must be reviewable: diff + validation + risks

Scope:
- In-scope: extended/cc-glm/scripts/generate-prompt.sh only
- Out-of-scope: No changes to SKILL.md, cc-glm-headless.sh, or cc-glm-job.sh
- Acceptance: Script generates valid prompts from template variables

Task:
- Create prompt compiler script under extended/cc-glm/scripts/
- Parse command-line args: beads, repo, wave_id, depends_on, scope
- Generate compliant prompt from template variables
- Validate required fields before output
- Include example in script usage

Expected outputs:
- Files changed: extended/cc-glm/scripts/generate-prompt.sh
- Diff: Full script content with template expansion
- Validation: bash -n extended/cc-glm/scripts/generate-prompt.sh passes
- Risks: Template changes may require script updates

Dependency context:
- depends_on: bd-3p27.2
- wave_id: wave-2
- wave_order: 1

Note: This task requires PROMPT_TEMPLATE_V8.1.md to exist first.
```

---

## Prompt Compiler Script Usage

### Basic Usage

```bash
~/agent-skills/extended/cc-glm/scripts/generate-prompt.sh \
  --beads bd-xxxx \
  --repo repo-name \
  --scope-in "src/**/*.ts" \
  --scope-out "tests,docs" \
  --task "Add error handling to API client" \
  --validation "npm run lint,npm test"
```

### With Wave Dependencies

```bash
~/agent-skills/extended/cc-glm/scripts/generate-prompt.sh \
  --beads bd-xxxx \
  --repo repo-name \
  --wave-id wave-2 \
  --depends-on bd-aaa,bd-bbb \
  --wave-order 2 \
  --scope-in "src/api/**/*.ts" \
  --scope-out "frontend,docs" \
  --task "Extend API client with retry logic" \
  --validation "npm run lint,npm test"
```

### Output File

Generated prompt written to: `/tmp/cc-glm-prompts/<beads-id>.prompt.txt`

Use with:

```bash
~/agent-skills/extended/cc-glm/scripts/cc-glm-job.sh start \
  --beads bd-xxxx \
  --repo repo-name \
  --prompt-file /tmp/cc-glm-prompts/bd-xxxx.prompt.txt
```

---

## Validation Commands

### Syntax Check

```bash
bash -n extended/cc-glm/scripts/*.sh
```

### Template Keyword Check

```bash
rg -n "wave_id|depends_on|Hard constraints|Expected outputs|Validation" extended/cc-glm -S
```

### Required Output Check

All delegated work MUST include:

1. **Files changed:** Explicit list of modified files
2. **Unified diff:** `git diff` or patch format
3. **Validation commands run:** With pass/fail status
4. **Risk notes:** Edge cases or unknowns

---

## Common Patterns

### 1. File Search/Replace Task

```text
Task:
- Replace all instances of "foo" with "bar" in src/**/*.ts
- Update imports if affected
- Run type check to verify

Expected outputs:
- Files changed: src/a.ts, src/b.ts
- Diff: Unified diff showing replacements
- Validation: npm run type-check passes
- Risks: None if type-check passes
```

### 2. Add Test Coverage Task

```text
Task:
- Add unit tests for src/utils/date.ts
- Cover parseDate, formatBytes, isValidDate functions
- Use existing test patterns in test/unit/

Expected outputs:
- Files changed: test/unit/date.test.ts
- Diff: New test file content
- Validation: npm test -- test/unit/date.test.ts passes
- Risks: May reveal existing bugs in date.ts
```

### 3. Documentation Update Task

```text
Task:
- Update README.md with new environment variables
- Add API_KEY and TIMEOUT_MS to env section
- Update example .env file

Expected outputs:
- Files changed: README.md, .env.example
- Diff: Unified diff of additions
- Validation: grep API_KEY README.md shows new content
- Risks: None (docs only)
```

---

## Troubleshooting

### "Missing required field"

Ensure all 4 header fields are present:
```text
Beads: <value>
Repo: <value>
Worktree: <value>
Agent: <value>
```

### "Scope not defined"

Ensure scope section has all three:
- In-scope: <concrete paths>
- Out-of-scope: <non-goals>
- Acceptance: <measurable criteria>

### "Invalid wave configuration"

- `depends_on` must contain valid Beads IDs
- `wave_order` must be >= 1
- `wave_id` must be consistent across all tasks in the wave

### "Output missing required sections"

Ensure output has:
- Files changed
- Diff
- Validation
- Risks

---

## Version History

- **8.1.0** (2026-02-11): Initial strict template specification
  - Required field definitions
  - Wave-based delegation pattern
  - Validation rules
  - Example prompts with dependencies
