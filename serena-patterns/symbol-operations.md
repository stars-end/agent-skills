# Symbol Operations Best Practices

Quick reference for Serena's symbolic tools with real-world examples.

## 🔍 Finding Symbols

### find_symbol - Primary Symbol Discovery Tool

**When to use**: Know the symbol name (class, function, variable) and want to read or modify it

**Basic usage**:
```bash
mcp__serena__find_symbol \
  --name-path-pattern "MyClass" \
  --include-body false  # Just metadata
```

**With body** (for editing):
```bash
mcp__serena__find_symbol \
  --name-path-pattern "MyClass" \
  --include-body true  # Full source code
  --depth 1  # Include methods (children)
```

### Name Path Patterns

| Pattern | Matches | Example |
|---------|---------|---------|
| `"method"` | Any symbol named "method" (anywhere in file) | `MyClass/method`, `OtherClass/method` |
| `"MyClass/method"` | Relative path | `MyClass/method` inside any file |
| `"/MyClass/method"` | Absolute path | Exact `MyClass/method` in file |
| `"MyClass/method[0]"` | Specific overload (Java/C++) | First `my_method` overload |
| `"get*"` | Substring matching | `getValue`, `getData`, `getName` |

**Pro tip**: Start with simple pattern, add specificity if too many matches

---

### get_symbols_overview - High-Level File View

**When to use**: First time exploring a file, want to see structure

**Usage**:
```bash
mcp__serena__get_symbols_overview \
  --relative-path "backend/api/portfolio.py"
```

**Output**: Top-level symbols (classes, functions) WITHOUT bodies

**Workflow**:
1. Overview first → See file structure
2. find_symbol next → Read specific symbol
3. replace_symbol_body → Modify if needed

---

### find_referencing_symbols - Who Uses This?

**When to use**: Before modifying a symbol, see impact

**Usage**:
```bash
mcp__serena__find_referencing_symbols \
  --name-path "calculate_returns" \
  --relative-path "backend/analytics.py"
```

**Output**: All symbols that call/import/reference `calculate_returns`

**Use cases**:
- Before renaming: See what breaks
- Before changing signature: Find all callers
- Understanding dependencies: Who depends on this?

---

## ✏️ Modifying Symbols

### replace_symbol_body - Primary Edit Tool

**When to use**: Replace entire symbol definition (function, class, method)

**Usage**:
```bash
mcp__serena__replace_symbol_body \
  --name-path "MyClass/method" \
  --relative-path "backend/services/user.py" \
  --body "def method(self, new_param: str):
    \"\"\"Updated docstring.\"\"\"
    # New implementation
    return result
"
```

**Important**: Body includes signature + docstring + implementation (NOT decorators above it)

**What counts as "body"**:
```python
# NOT part of body (don't include):
@decorator
@another_decorator

# YES part of body (include this):
def method(self, param):
    """Docstring"""
    return result
```

---

### insert_after_symbol - Add Code After

**When to use**: Add new function/class/method after existing one

**Usage**:
```bash
mcp__serena__insert_after_symbol \
  --name-path "existing_function" \
  --relative-path "backend/utils.py" \
  --body "def new_function(param: str) -> str:
    \"\"\"New function added after existing_function.\"\"\"
    return result
"
```

**Use cases**:
- Add new method to class (insert after last method)
- Add new function to module (insert after existing function)
- Maintain logical grouping (related functions together)

---

### insert_before_symbol - Add Code Before

**When to use**: Add new code before existing symbol

**Usage**:
```bash
mcp__serena__insert_before_symbol \
  --name-path "main_function" \
  --relative-path "backend/app.py" \
  --body "def helper_function():
    \"\"\"Helper for main_function.\"\"\"
    pass
"
```

**Use cases**:
- Add helper before main function
- Add import before first symbol (use first top-level symbol as anchor)
- Add new class before existing class

---

### rename_symbol - Refactor Across Codebase

**When to use**: Rename class/function/variable everywhere

**Usage**:
```bash
mcp__serena__rename_symbol \
  --name-path "OldClassName" \
  --relative-path "backend/models/user.py" \
  --new-name "NewClassName"
```

**What it does**:
- Renames symbol definition
- Updates ALL references across entire codebase
- Updates imports
- Safe refactoring

**Limitations**: Only works for symbols Serena can track (not string literals)

---

## 🎯 Workflow Patterns

### Pattern 1: Explore → Read → Edit

```bash
# 1. Overview (what's in this file?)
mcp__serena__get_symbols_overview --relative-path "file.py"

# 2. Read specific symbol
mcp__serena__find_symbol \
  --name-path-pattern "TargetClass" \
  --include-body true

# 3. Edit
mcp__serena__replace_symbol_body \
  --name-path "TargetClass" \
  --body "class TargetClass:..."
```

---

### Pattern 2: Impact Analysis → Edit

```bash
# 1. Find symbol to change
mcp__serena__find_symbol \
  --name-path-pattern "old_method" \
  --include-body true

# 2. See who uses it
mcp__serena__find_referencing_symbols \
  --name-path "old_method" \
  --relative-path "file.py"

# 3. If safe, rename or modify
mcp__serena__rename_symbol \
  --name-path "old_method" \
  --new-name "new_method"
```

---

### Pattern 3: Add New Code to Existing Structure

```bash
# 1. Find insertion point (e.g., last method in class)
mcp__serena__find_symbol \
  --name-path-pattern "MyClass" \
  --depth 1  # See all methods

# 2. Insert after last method
mcp__serena__insert_after_symbol \
  --name-path "MyClass/last_method" \
  --body "def new_method(self):..."
```

---

## 📊 Parameter Reference

### find_symbol Parameters

| Parameter | Type | Default | Purpose |
|-----------|------|---------|---------|
| `name-path-pattern` | string | required | Symbol name or path pattern |
| `relative-path` | string | `""` | Restrict to file/directory |
| `include-body` | bool | `false` | Include source code |
| `depth` | int | `0` | Include children (1=direct, 2=grandchildren) |
| `substring-matching` | bool | `false` | "get" matches "getValue" |
| `include-kinds` | int[] | all | Filter by LSP symbol kind |
| `exclude-kinds` | int[] | none | Exclude LSP symbol kinds |

### LSP Symbol Kinds (for filtering)

| Kind | Number | Examples |
|------|--------|----------|
| File | 1 | - |
| Module | 2 | Python modules, TS modules |
| Class | 5 | `class MyClass` |
| Method | 6 | `def method(self)` |
| Function | 12 | `def function()` |
| Variable | 13 | `my_var = ...` |
| Constant | 14 | `MY_CONST = ...` |

**Example**:
```bash
# Find only classes, exclude methods
mcp__serena__find_symbol \
  --name-path-pattern "User" \
  --include-kinds [5]  # Only classes
  --exclude-kinds [6]  # Exclude methods
```

---

## 🐛 Common Mistakes & Fixes

### ❌ Mistake 1: Reading Entire File

```bash
# WRONG (inefficient)
Read("backend/services/user.py")  # Reads all 500 lines

# RIGHT (targeted)
mcp__serena__get_symbols_overview --relative-path "backend/services/user.py"
# Then:
mcp__serena__find_symbol --name-path "create_user" --include-body true
```

---

### ❌ Mistake 2: Modifying Without Reading First

```bash
# WRONG (blind edit)
mcp__serena__replace_symbol_body --name-path "method" --body "new code"

# RIGHT (read first)
mcp__serena__find_symbol --name-path "method" --include-body true
# Review body, then:
mcp__serena__replace_symbol_body --name-path "method" --body "new code"
```

---

### ❌ Mistake 3: Forgetting to Check References

```bash
# WRONG (rename without checking)
mcp__serena__rename_symbol --name-path "old_func" --new-name "new_func"

# RIGHT (check impact first)
mcp__serena__find_referencing_symbols --name-path "old_func"
# Review callers, THEN rename if safe
```

---

### ❌ Mistake 4: Wrong Name Path

```bash
# WRONG (too vague)
--name-path-pattern "method"  # Matches 50 methods

# RIGHT (specific)
--name-path-pattern "UserService/create_user"  # Exact match
```

---

### ❌ Mistake 5: Including Decorators in Body

```python
# WRONG body (includes decorator)
body = "@app.get('/users')
def get_users():
    return users
"

# RIGHT body (decorator NOT part of symbol body)
body = "def get_users():
    return users
"
```

**Note**: Serena manages decorators separately from symbol body

---

## 🎓 Learning Path

### Beginner: Exploration

1. Start with `get_symbols_overview` on files
2. Use `find_symbol` with `include-body=false` to explore
3. Practice reading bodies with `include-body=true`

### Intermediate: Editing

1. Use `replace_symbol_body` for simple edits
2. Use `insert_after_symbol` / `insert_before_symbol` for additions
3. Always read before editing

### Advanced: Refactoring

1. Use `find_referencing_symbols` before changes
2. Use `rename_symbol` for safe renaming
3. Combine search + symbolic tools for complex refactorings

---

## 📚 Related

- **Common Searches**: [common-searches.md](common-searches.md) - search_for_pattern examples
- **Refactoring Recipes**: [refactoring-recipes.md](refactoring-recipes.md) - Multi-step refactorings
- **Official Serena Docs**: https://github.com/oraios/serena/blob/main/README.md

---

## 💡 Pro Tips

1. **Depth parameter**: `depth=0` (symbol only), `depth=1` (+ children), `depth=2` (+ grandchildren)
2. **Substring matching**: Useful for finding all getters: `name-path-pattern="get*" substring-matching=true`
3. **Symbol kinds**: Filter noise by excluding variables/constants if only want functions/classes
4. **Relative path**: Always scope to file/directory when possible (faster, fewer false positives)
5. **include-body**: Only include when editing (saves tokens for exploration)
6. **Name path hierarchy**: More specific = faster search (absolute path > relative > simple name)

**Golden rule**: Narrow your search as much as possible (file > kind > name path > depth)
