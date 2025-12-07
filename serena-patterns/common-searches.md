# Common Search Patterns for Serena

Frequently used search patterns to speed up codebase navigation.

## 🔍 API Endpoints

### Find All FastAPI Routes
```
Pattern: @(app|router)\.(get|post|put|delete|patch)
Files: *.py
Purpose: Locate all API endpoints
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern '@(app|router)\.(get|post|put|delete|patch)' \
  --paths-include-glob '**/*.py' \
  --context-lines-before 2 \
  --context-lines-after 5
```

**Use case**: Understanding API surface, finding endpoint to modify

---

### Find All Route Definitions by Path
```
Pattern: @.*\("(/[^"]*)"
Purpose: Extract all URL paths defined in routes
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern '@.*\("(/[^"]*)"' \
  --paths-include-glob 'backend/api/**/*.py'
```

**Use case**: API documentation, checking for path conflicts

---

## 🗄️ Database Queries

### Find All SQLAlchemy Queries
```
Pattern: session\.(query|execute|add|commit|delete)
Files: backend/**/*.py
Purpose: Locate database operations
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern 'session\.(query|execute|add|commit|delete)' \
  --relative-path 'backend/' \
  --paths-include-glob '**/*.py' \
  --context-lines-after 3
```

**Use case**: Auditing database access, finding N+1 queries

---

### Find All Migrations
```
Pattern: def upgrade|def downgrade
Files: supabase/migrations/*.sql
Purpose: List all migration operations
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern 'CREATE TABLE|ALTER TABLE|DROP TABLE' \
  --relative-path 'supabase/migrations/' \
  --paths-include-glob '*.sql'
```

**Use case**: Schema changes audit, migration timeline

---

## ⚛️ React Components

### Find All Component Definitions
```
Pattern: (export (default )?function|export const \w+ = |const \w+: React\.FC)
Files: frontend/**/*.tsx
Purpose: Locate all React components
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern 'export (default )?function|export const \w+ = .*=>|const \w+: React\.FC' \
  --relative-path 'frontend/src' \
  --paths-include-glob '**/*.tsx' \
  --context-lines-after 10
```

**Use case**: Component inventory, finding component to modify

---

### Find All useState/useEffect Hooks
```
Pattern: use(State|Effect|Callback|Memo|Ref)\(
Files: frontend/**/*.tsx
Purpose: Locate stateful logic in components
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern 'use(State|Effect|Callback|Memo|Ref|Context)\(' \
  --relative-path 'frontend/src' \
  --context-lines-before 1 \
  --context-lines-after 3
```

**Use case**: Understanding component state, debugging re-renders

---

## 🔐 Authentication & Security

### Find All Auth Checks
```
Pattern: @require.*auth|clerk\.|check.*permission
Files: backend/**/*.py
Purpose: Locate authentication/authorization code
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern '@require.*auth|clerk\.|check.*permission|verify.*token' \
  --relative-path 'backend/' \
  --paths-include-glob '**/*.py' \
  --context-lines-after 5
```

**Use case**: Security audit, finding protected endpoints

---

### Find All API Keys/Secrets References
```
Pattern: (API_KEY|SECRET_KEY|TOKEN|PASSWORD)
Files: **/*.py, **/*.ts
Purpose: Locate environment variable usage
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern '(API_KEY|SECRET_KEY|TOKEN|PASSWORD|SUPABASE_URL)' \
  --paths-exclude-glob '**/*.lock,**/node_modules/**' \
  --context-lines-before 2
```

**Use case**: Secrets audit, environment variable tracking

---

## 🧪 Tests

### Find All Test Functions
```
Pattern: def test_|it\("|describe\("
Files: tests/**/*.py, **/*.test.ts
Purpose: Locate all test cases
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern 'def test_|it\("|describe\("' \
  --paths-include-glob 'tests/**/*.py,**/*.test.ts' \
  --context-lines-after 5
```

**Use case**: Test coverage analysis, finding tests for feature

---

### Find All Fixtures
```
Pattern: @pytest\.fixture|@fixture
Files: tests/**/*.py
Purpose: Locate test fixtures
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern '@pytest\.fixture|@fixture' \
  --relative-path 'backend/tests/' \
  --context-lines-after 10
```

**Use case**: Understanding test setup, reusing fixtures

---

## 📝 Documentation

### Find All TODOs/FIXMEs
```
Pattern: (TODO|FIXME|XXX|HACK|NOTE):
Purpose: Locate code comments needing attention
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern '(TODO|FIXME|XXX|HACK|NOTE):' \
  --paths-exclude-glob '**/node_modules/**,**/.venv/**' \
  --context-lines-before 1 \
  --context-lines-after 2
```

**Use case**: Technical debt tracking, refactoring planning

---

### Find All Docstrings
```
Pattern: """.*"""|\'\'\'.*\'\'\'
Files: **/*.py
Purpose: Locate documented functions/classes
```

**Example (multiline)**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern '""".*?"""' \
  --multiline true \
  --relative-path 'backend/' \
  --paths-include-glob '**/*.py'
```

**Use case**: Documentation coverage, API reference generation

---

## 🔧 Configuration

### Find All Environment Variable Reads
```
Pattern: os\.getenv|os\.environ\[|process\.env\.
Purpose: Locate all config reads
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern 'os\.getenv|os\.environ\[|process\.env\.' \
  --context-lines-before 1 \
  --context-lines-after 1
```

**Use case**: Environment variable inventory, config audit

---

### Find All Settings/Config Classes
```
Pattern: class.*Settings|class.*Config
Files: **/*.py
Purpose: Locate configuration classes
```

**Example**:
```bash
mcp__serena__search_for_pattern \
  --substring-pattern 'class.*(Settings|Config)' \
  --paths-include-glob '**/*.py' \
  --context-lines-after 20
```

**Use case**: Understanding app configuration, adding new settings

---

## 📊 Usage Tips

### When to Use search_for_pattern vs find_symbol

| Use search_for_pattern when: | Use find_symbol when: |
|------------------------------|----------------------|
| Pattern-based search (regex) | Know exact symbol name |
| Finding across all files | Finding specific class/method |
| Discovering unknowns | Reading symbol body |
| Documentation, comments | Code-only search |

### Optimizing Searches

1. **Use relative_path** to narrow scope:
   ```bash
   --relative-path 'backend/api/'  # Only search api/ directory
   ```

2. **Use glob patterns** to filter files:
   ```bash
   --paths-include-glob '**/*.py'  # Only Python files
   --paths-exclude-glob '**/tests/**'  # Skip tests
   ```

3. **Adjust context lines**:
   ```bash
   --context-lines-after 5  # More context for understanding
   --context-lines-before 1  # Less context for lists
   ```

4. **Use multiline** for complex patterns:
   ```bash
   --multiline true  # For patterns spanning multiple lines
   ```

### Common Mistakes

❌ **Too broad**: `search_for_pattern("function")`
✅ **Specific**: `search_for_pattern("def.*api.*:", paths-include-glob="backend/api/**")`

❌ **Reading whole file**: `Read(file.py)` then manual search
✅ **Targeted search**: `search_for_pattern("pattern", relative-path="file.py")`

❌ **No context**: `context-lines-after=0`
✅ **Enough context**: `context-lines-after=5` (see usage, not just match)

---

## 📚 Related

- **Refactoring Recipes**: [refactoring-recipes.md](refactoring-recipes.md) - Multi-step operations
- **Symbol Operations**: [symbol-operations.md](symbol-operations.md) - find_symbol, replace_symbol_body
- **Official Docs**: https://github.com/oraios/serena/blob/main/README.md
