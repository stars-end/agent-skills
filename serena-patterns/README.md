# Serena Patterns

Curated knowledge base for effective Serena MCP usage.

## 📚 What's Inside

| Guide | Purpose | When to Use |
|-------|---------|-------------|
| [common-searches.md](common-searches.md) | Frequently used search patterns | Finding API endpoints, database queries, React components, etc. |
| [refactoring-recipes.md](refactoring-recipes.md) | Step-by-step refactoring guides | Rename class, extract method, move function, add decorators |
| [symbol-operations.md](symbol-operations.md) | Best practices for symbolic tools | find_symbol, replace_symbol_body, insert operations |

## 🎯 Quick Start

### New to Serena?

**Start here**: [symbol-operations.md](symbol-operations.md)

Learn the workflow:
1. `get_symbols_overview` - See file structure
2. `find_symbol` - Read specific symbol
3. `replace_symbol_body` - Modify code
4. `find_referencing_symbols` - Check impact

### Need to Find Something?

**Go to**: [common-searches.md](common-searches.md)

Find pre-built patterns for:
- API endpoints (`@app.get`, `@router.post`)
- Database queries (`session.execute`, `query()`)
- React components (`export function`, `useState`)
- Auth checks (`@require_auth`, `clerk.`)
- Tests (`def test_`, `it("`)

### Refactoring Code?

**Check**: [refactoring-recipes.md](refactoring-recipes.md)

Step-by-step guides for:
- Rename class across codebase
- Extract method from long function
- Add parameter to multiple functions
- Move function to different module
- Convert class to dataclass

## 🔍 Search vs Symbolic Tools

### When to Use search_for_pattern

✅ Pattern-based discovery (regex)
✅ Finding across all files
✅ Don't know exact symbol name
✅ Include comments/docs/non-code

**Example**: Find all API endpoints
```bash
mcp__serena__search_for_pattern \
  --substring-pattern '@app\.(get|post|put)' \
  --paths-include-glob 'backend/api/**/*.py'
```

### When to Use find_symbol

✅ Know exact symbol name
✅ Want symbol body for editing
✅ Need type information
✅ Code-only search (skip comments)

**Example**: Read specific class
```bash
mcp__serena__find_symbol \
  --name-path-pattern "UserService" \
  --include-body true \
  --depth 1  # Include methods
```

**Best practice**: search_for_pattern for discovery → find_symbol for editing

---

## 🎓 Learning Path

### Week 1: Exploration
- Read [symbol-operations.md](symbol-operations.md) basics section
- Practice `get_symbols_overview` on 5-10 files
- Use `find_symbol` to read classes/functions
- Try `include-body=true` vs `false`

**Exercise**: Explore 3 files you've never seen before using only Serena tools

### Week 2: Searching
- Read [common-searches.md](common-searches.md)
- Practice API endpoint search
- Find all database queries in a service
- Search for TODOs/FIXMEs

**Exercise**: Create 3 custom search patterns for your codebase

### Week 3: Editing
- Use `replace_symbol_body` for simple changes
- Try `insert_after_symbol` to add new methods
- Practice reading before editing

**Exercise**: Refactor 1 function (read → understand → replace)

### Week 4: Refactoring
- Read [refactoring-recipes.md](refactoring-recipes.md)
- Use `find_referencing_symbols` before changes
- Try `rename_symbol` on safe refactoring
- Complete multi-step refactoring with TodoWrite

**Exercise**: Rename a class and update all references

---

## 💡 Pro Tips

### Tip 1: Narrow Your Scope
```bash
# BAD (searches entire project)
mcp__serena__find_symbol --name-path-pattern "method"

# GOOD (specific file)
mcp__serena__find_symbol \
  --name-path-pattern "method" \
  --relative-path "backend/api/portfolio.py"
```

### Tip 2: Use Context Lines
```bash
# Search with context to understand usage
mcp__serena__search_for_pattern \
  --substring-pattern "session.execute" \
  --context-lines-before 3 \
  --context-lines-after 5
```

### Tip 3: Check References Before Editing
```bash
# Always check impact first
mcp__serena__find_referencing_symbols \
  --name-path "function_to_change" \
  --relative-path "module.py"
```

### Tip 4: Read Before Replacing
```bash
# DON'T replace blindly
# DO read current body first
mcp__serena__find_symbol --name-path "func" --include-body true
# Then replace
```

### Tip 5: Use Depth Wisely
```bash
# depth=0: Just the symbol
# depth=1: Symbol + immediate children (methods of class)
# depth=2: Symbol + children + grandchildren (rare)
```

---

## 🐛 Common Mistakes

### Mistake 1: Reading Entire Files
**Wrong**: `Read("backend/services/user.py")` (500 lines)
**Right**: `get_symbols_overview` then `find_symbol` for specific parts

### Mistake 2: Forgetting to Check References
**Wrong**: Change function signature without checking callers
**Right**: `find_referencing_symbols` first, then update callers

### Mistake 3: Too Broad Searches
**Wrong**: `find_symbol --name-path "get"` (matches 100 symbols)
**Right**: `find_symbol --name-path "UserService/get_user"`

### Mistake 4: No Context in Searches
**Wrong**: Search with `context-lines-after=0` (just the match line)
**Right**: Use `context-lines-after=5` to understand usage

### Mistake 5: Including Decorators in Body
**Wrong**: `body = "@app.get('/users')\ndef get_users()..."`
**Right**: `body = "def get_users()..."` (decorators separate)

---

## 📊 Serena vs Traditional Tools

| Operation | Traditional | Serena | Benefit |
|-----------|-------------|--------|---------|
| Find all API endpoints | `grep -r "@app.get"` | `search_for_pattern` | Respects .gitignore, better grouping |
| Read specific class | `cat file.py \| less` | `find_symbol --include-body` | Exact symbol, not whole file |
| Rename across files | Manual find/replace | `rename_symbol` | Safe, updates references |
| Find usages | `grep -r "function_name"` | `find_referencing_symbols` | Code-aware, skips comments |
| File structure | `head -100 file.py` | `get_symbols_overview` | Symbol metadata, no bodies |

**Key advantage**: Serena is **code-aware** (understands symbols, not just text)

---

## 🔗 Integration with Agent Workflows

### AGENTS.md Rule: "Serena-first for code operations"

```bash
# ❌ DON'T use bash grep
bash grep -r "function" .

# ✅ DO use Serena search
mcp__serena__search_for_pattern --substring-pattern "function"

# ❌ DON'T use bash cat
bash cat backend/services/user.py

# ✅ DO use Serena overview + find_symbol
mcp__serena__get_symbols_overview --relative-path "backend/services/user.py"
mcp__serena__find_symbol --name-path "UserService" --include-body true
```

### With Beads Issue-First Pattern

```bash
# 1. Create Beads issue BEFORE refactoring
bd create "Refactor UserService" --type task

# 2. Use Serena to understand code
mcp__serena__get_symbols_overview --relative-path "backend/services/user.py"
mcp__serena__find_symbol --name-path "UserService" --include-body true

# 3. Use refactoring recipes from this guide
# (See refactoring-recipes.md)

# 4. Commit with Feature-Key
git commit -m "refactor: Simplify UserService

Feature-Key: bd-xyz
Agent: claude-code
Role: backend-engineer"
```

---

## 🆘 When Serena Can't Help

### Use Traditional Tools For:

1. **Non-code files**: Markdown, JSON, YAML
   - Use `Read`, `Grep`, or `Bash`

2. **String literals in code**: Finding hardcoded strings
   - Use `search_for_pattern` (still Serena, not find_symbol)

3. **Cross-repo searches**: Searching multiple repos
   - Use `Bash` with grep

4. **Binary files**: Images, PDFs
   - Use appropriate tools (Read for PDFs)

5. **Generated code**: Lock files, build artifacts
   - Usually don't need to search these

---

## 📚 External Resources

- **Official Serena Docs**: https://github.com/oraios/serena/blob/main/README.md
- **Serena GitHub**: https://github.com/oraios/serena
- **LSP Spec**: https://microsoft.github.io/language-server-protocol/ (for symbol kinds)

---

## 🔮 Future Enhancements

Ideas for expanding this knowledge base:

1. **Language-specific guides**: Python, TypeScript, React patterns
2. **Performance tips**: Optimizing slow searches
3. **Advanced patterns**: Multi-file refactorings, AST manipulation
4. **Integration examples**: With Claude Code skills, Beads workflows
5. **Video walkthroughs**: Screen recordings of common operations

**Contribute**: If you discover useful patterns, document them here!

---

**Last Updated**: 2025-12-07
**Part of**: agent-skills restructure (bd-v9z0)
**See Also**: GitHub Actions composite actions, deployment tooling
