# Ralph Task Suitability Analysis

## Executive Summary

This document analyzes task patterns for Ralph autonomous agent execution, identifying what works well, common failure modes, and recommended criteria for task selection.

---

## 1. Task Types That Work Well

### High-Suitability Task Categories

#### **File Operations**
- ✅ Create new files with specified content
- ✅ Add trailing newlines to text files
- ✅ Simple file copying/moving
- ✅ Git add operations on created files

**Why it works:**
- Clear, unambiguous success criteria
- Direct mapping from requirement to action
- Minimal context switching needed
- Easy to verify completion

#### **Documentation Tasks**
- ✅ Write simple markdown documents
- ✅ Update README files
- ✅ Create comment blocks
- ✅ Document API contracts

**Why it works:**
- Output format well-defined (Markdown, plain text)
- Content can be fully specified in task description
- No complex dependencies or side effects
- Self-contained work

#### **Configuration Management**
- ✅ Create/update config files (JSON, YAML, TOML)
- ✅ Add environment variable definitions
- ✅ Set up toolchain configurations

**Why it works:**
- Structured format with clear syntax
- No business logic to implement
- Validation is straightforward (parse the file)

#### **Git Mechanics**
- ✅ Create commits with specified messages
- ✅ Add files to staging
- ✅ Create branches (if no conflicts)
- ✅ Tag operations

**Why it works:**
- Well-defined Git CLI interface
- Deterministic outcomes
- Clear error messages when operations fail

### Task Characteristics for Success

| Characteristic | Description | Example |
|----------------|-------------|---------|
| **Self-Contained** | No external dependencies beyond local file system | Create `t1.txt` with "Task 1" |
| **Single-Action** | Can be completed in one logical step | Add trailing newline to file |
| **Unambiguous** | Clear, single correct interpretation | Update line 42 to say "completed" |
| **Verifiable** | Easy to check if task succeeded | File exists with correct content |
| **Low-Risk** | Mistakes easily reversible | Git add on test file |

---

## 2. What Causes Failures

### Primary Failure Categories

#### **Ambiguous Requirements**
**Failure Pattern:** Task description leaves interpretation gaps
```
❌ "Update the documentation"
✅ "Add a section about X to docs/api.md after the existing overview"
```

**Why it fails:**
- Agent must guess scope and intent
- Multiple valid interpretations possible
- Founder's mental model not fully captured

#### **Multi-Step Dependencies**
**Failure Pattern:** Task requires multiple coordinated actions
```
❌ "Fix the authentication flow"
✅ "Update the validate_token function to return boolean instead of string"
```

**Why it fails:**
- Requires understanding complex system interactions
- One failure blocks entire task
- Context tracking across multiple operations

#### **External System Integration**
**Failure Pattern:** Task involves APIs, databases, or services
```
❌ "Deploy the app to Railway"
✅ "Create the railway.json file with the following configuration"
```

**Why it fails:**
- Authentication and state management required
- Network conditions affect success
- Error messages may be cryptic
- Side effects hard to roll back

#### **Irreversible Operations**
**Failure Pattern:** Task cannot be safely undone
```
❌ "Delete all unused branches"
✅ "List branches not merged to master for review"
```

**Why it fails:**
- No safety net for mistakes
- Agent cannot verify correctness before acting
- Cost of failure is high

#### **Context-Heavy Requirements**
**Failure Pattern:** Task requires deep domain knowledge
```
❌ "Optimize the database queries"
✅ "Replace the JOIN on line 156 with a subquery as shown in PR #234"
```

**Why it fails:**
- Requires understanding of business logic
- Performance implications nuanced
- Trade-offs need human judgment

### Failure Severity Matrix

| Severity | Example | Recovery |
|----------|---------|----------|
| **Critical** | `git reset --hard`, `rm -rf` | Requires backup restore |
| **High** | Breaking production changes | Rollback, hotfix |
| **Medium** | Wasted time on wrong approach | Discard, retry |
| **Low** | Minor formatting issues | Easy fix |

---

## 3. Common Error Patterns

### Pattern 1: Over-Specification

**What happens:**
- Task description is too detailed
- Agent follows instructions literally
- Misses the actual intent

**Example:**
```
Task: "Create a file called t1.txt in the current directory, 
       open it, write the text 'Task 1', then save it and close it"
Issue: Agent might create multiple intermediate files or states
```

**Better approach:**
```
Task: "Create t1.txt with content 'Task 1'"
```

### Pattern 2: Implicit Assumptions

**What happens:**
- Founder assumes agent knows context
- Agent lacks critical information
- Task fails or produces wrong result

**Example:**
```
Task: "Update the API documentation"
Missing: Which file? Which API? What changes?
```

**Better approach:**
```
Task: "Add the new /v2/users endpoint to docs/api.md 
       after the /v1/users section"
```

### Pattern 3: Scope Creep

**What happens:**
- Task sounds simple but has hidden complexity
- Agent starts task but can't complete
- Partial state left behind

**Example:**
```
Task: "Add error handling"
Reality: Requires understanding error domains, 
         logging infrastructure, user notifications, etc.
```

**Better approach:**
```
Task: "Add try-catch around the database call 
       and log the error message"
```

### Pattern 4: Success Criteria Ambiguity

**What happens:**
- Task complete but unclear if it succeeded
- Agent outputs completion signal prematurely
- Founder must manually verify

**Example:**
```
Task: "Fix the build"
Result: Build passes but test coverage dropped
```

**Better approach:**
```
Task: "Fix the build error in test_api.py line 42
       without breaking any existing tests"
```

### Pattern 5: Tool Confusion

**What happens:**
- Agent uses wrong tool for the job
- Creates convoluted solutions
- Ignores available better options

**Example:**
```
Task: "List all files"
Bad: Uses Bash to run `ls`, then parses output
Good: Uses Glob tool with pattern "*"
```

### Pattern 6: State Assumption Violations

**What happens:**
- Task assumes file/directory exists
- Agent tries to work on non-existent resources
- Fails with cryptic errors

**Example:**
```
Task: "Update line 42 of config.yaml"
Reality: File doesn't exist or has different structure
```

**Better approach:**
```
Task: "If config.yaml exists, update line 42. 
       Otherwise, create it with this structure..."
```

---

## 4. Recommended Task Criteria for Ralph

### Task Suitability Checklist

Use this checklist to evaluate if a task is suitable for Ralph autonomous execution.

#### Must-Have Criteria (All Required)

- [ ] **Single Atomic Action**: Task can be completed in one logical operation
- [ ] **Unambiguous Specification**: Clear, single correct interpretation possible
- [ ] **Self-Contained**: No external dependencies (API calls, services, network)
- [ ] **Verifiable Success**: Easy to check if task succeeded (file exists, content matches)
- [ ] **Low-Risk**: Mistakes are easily reversible or low impact
- [ ] **Explicit Output Format**: Expected output clearly specified (file path, content)

#### Should-Have Criteria (Most Should Apply)

- [ ] **No Context Switching**: Doesn't require reading multiple files to understand
- [ ] **No Business Logic**: Purely mechanical/structural work
- [ ] **Deterministic Outcome**: Same input always produces same output
- [ ] **No State Dependencies**: Doesn't depend on current branch, environment, etc.
- [ ] **Clear Success Signal**: Can output IMPLEMENTATION_COMPLETE with confidence

#### Nice-to-Have Criteria

- [ ] **Idempotent**: Can run multiple times safely
- [ ] **No Side Effects**: Only affects specified files/resources
- [ ] **Fast Execution**: Completes in < 30 seconds
- [ ] **No Compilation/Build**: Doesn't require running build/test suite

### Task Scoring Matrix

Assign points for each criterion met. Total score determines suitability:

| Criteria | Points |
|----------|--------|
| Single Atomic Action | 20 |
| Unambiguous Specification | 20 |
| Self-Contained | 20 |
| Verifiable Success | 15 |
| Low-Risk | 15 |
| Explicit Output Format | 10 |

**Scoring:**
- **100-90 points**: ✅ Excellent candidate - Proceed autonomously
- **89-70 points**: ⚠️  Good candidate - Proceed with caution
- **69-50 points**: ❌ Marginal - Consider breaking down
- **< 50 points**: 🚫 Not suitable - Requires human guidance

### Task Transformation Examples

#### Example 1: Break Down Complex Task

**Original (Score: 30):**
```
"Set up the development environment for the project"
```

**Transformed (Three tasks, each Score: 100):**
```
1. "Create .env.example with DATABASE_URL, API_KEY placeholders"
2. "Create .mise.toml with tools: nodejs@20, python@3.11"
3. "Create scripts/setup.sh that runs mise install"
```

#### Example 2: Add Specificity

**Original (Score: 60):**
```
"Update the README"
```

**Transformed (Score: 100):**
```
"Add a 'Quick Start' section to README.md after the 'Installation' section 
with the following 3 steps..."
```

#### Example 3: Remove Dependencies

**Original (Score: 40):**
```
"Deploy the application to Railway and verify it works"
```

**Transformed (Score: 100):**
```
"Create railway.json with the service configuration for frontend deployment"
```

### Task Template for Ralph

Use this template for creating Ralph-suitable tasks:

```markdown
## Task: [Short, Clear Title]

### Objective
[One sentence description of what to accomplish]

### Action Required
[Specific instruction in format: Create/Update/Delete [file] with [content]]

### Expected Output
- File path: [absolute path]
- Content: [exact content or clear specification]

### Success Criteria
- [ ] File exists at specified path
- [ ] Content matches specification exactly
- [ ] No additional files modified
- [ ] Trailing newline present (if text file)

### Risk Level: Low/Medium/High
[Justification]
```

### Anti-Patterns to Avoid

❌ **Do NOT create tasks that:**
- Require reading multiple files to understand context
- Depend on network services or APIs
- Need authentication or secrets
- Have ambiguous success criteria
- Require human judgment or decisions
- Are irreversible without consequences
- Need to run complex build/test pipelines

✅ **DO create tasks that:**
- Are clearly specified in one instruction
- Affect only the files/resources mentioned
- Can be verified with simple checks
- Are safe to retry if they fail
- Follow established patterns in the codebase
- Have clear, unambiguous success criteria

---

## 5. Best Practices for Task Design

### Principle 1: Specificity Over Generality

**Bad:** "Improve the documentation"
**Good:** "Add a paragraph to docs/API.md explaining the error handling strategy"

### Principle 2: Explicit Over Implicit

**Bad:** "Update the config"
**Good:** "Update config/development.json to set DEBUG=false"

### Principle 3: Atomic Over Composite

**Bad:** "Set up the whole project"
**Good:** "Create package.json with the specified dependencies"

### Principle 4: Verifiable Over Ambiguous

**Bad:** "Make the code cleaner"
**Good:** "Extract lines 45-52 into a function named validate_input"

### Principle 5: Safe Over Risky

**Bad:** "Delete all the temp files"
**Good:** "Create a list of temp files in /tmp for review"

---

## 6. Decision Framework

### Should I Assign This to Ralph?

Ask these questions:

1. **Can I specify exactly what the output should be?**
   - Yes → Continue
   - No → Refine or assign to human

2. **Does this require reading more than 2-3 files to understand?**
   - No → Continue
   - Yes → Break down or assign to human

3. **Does this touch any external systems?**
   - No → Continue
   - Yes → Assign to human

4. **If Ralph does this wrong, can I fix it in < 1 minute?**
   - Yes → Continue
   - No → Assign to human

5. **Is there exactly one correct way to do this?**
   - Yes → Assign to Ralph
   - No → Refine specification

### Flowchart for Task Assignment

```
Start
  ↓
Is task self-contained? 
  ├─ No → Assign to human
  └─ Yes ↓
Is task atomic?
  ├─ No → Break down
  └─ Yes ↓
Is success verifiable?
  ├─ No → Refine criteria
  └─ Yes ↓
Is risk low?
  ├─ No → Assign to human
  └─ Yes → ASSIGN TO RALPH
```

---

## 7. Monitoring and Feedback

### Task Success Indicators

Monitor these metrics to assess Ralph's effectiveness:

- **Success Rate**: % of tasks completed without intervention
- **Retry Rate**: % of tasks that needed multiple attempts
- **Rejection Rate**: % of tasks rejected as unsuitable
- **Intervention Rate**: % of tasks requiring human assistance

### When to Adjust Criteria

**Success rate < 80%**: Tasks are too complex → Tighten criteria
**Success rate > 95%**: May be missing opportunities → Loosen slightly
**Retry rate > 20%**: Specifications are unclear → Improve templates

---

## Appendix: Examples

### Example 1: Perfect Ralph Task (Score: 100)

```markdown
## Task: Add trailing newline to t1.txt

### Action Required
Add a trailing newline to /Users/fengning/project/t1.txt

### Expected Output
- File: /Users/fengning/project/t1.txt
- Change: Empty line added at end of file

### Success Criteria
- [ ] File exists
- [ ] File ends with newline character
- [ ] No other modifications

### Risk Level: Low
```

### Example 2: Good Ralph Task (Score: 85)

```markdown
## Task: Create config file

### Action Required
Create .mise.toml in /Users/fengning/project/ with the following content:
```
[tools]
nodejs = "20.11.0"
python = "3.11.7"
```

### Expected Output
- File: /Users/fengning/project/.mise.toml
- Content: Exactly as specified above

### Success Criteria
- [ ] File created at correct path
- [ ] Content matches specification
- [ ] File includes trailing newline

### Risk Level: Low
```

### Example 3: Marginal Ralph Task (Score: 55)

```markdown
## Task: Update script

### Action Required
Update the error handling in scripts/deploy.sh to be more robust

### Expected Output
- File: scripts/deploy.sh
- Change: Better error handling

### Success Criteria
- [ ] Script works better
- [ ] Fewer errors occur

### Risk Level: Medium

**Analysis:** Too ambiguous. "More robust" is subjective.
"Better" is not verifiable. Requires understanding the script's logic.
```

### Example 4: Unsuitable Ralph Task (Score: 25)

```markdown
## Task: Fix authentication

### Action Required
Fix the authentication issues users are experiencing

### Expected Output
- Authentication works

### Success Criteria
- [ ] Users can log in

### Risk Level: High

**Analysis:** Requires investigating the issue, understanding the 
auth system, testing, deployment. High risk of breaking things. 
Definitely requires human intervention.
```

---

## Conclusion

Ralph excels at **atomic, self-contained, low-risk tasks** with clear specifications. The key to success is breaking complex work into small, verifiable units that can be completed autonomously without ambiguity or external dependencies.

When in doubt: **Make tasks smaller, more specific, and easier to verify.**

