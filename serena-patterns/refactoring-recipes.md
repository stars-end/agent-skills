# Refactoring Recipes with Serena

Step-by-step guides for common refactoring operations using Serena's symbolic tools.

## 🔄 Recipe 1: Rename Class Across Codebase

**Goal**: Rename `UserAccount` → `Account` everywhere

### Steps

1. **Find the class**:
   ```bash
   mcp__serena__find_symbol \
     --name-path-pattern "UserAccount" \
     --include-body false
   ```

2. **Find all references**:
   ```bash
   mcp__serena__find_referencing_symbols \
     --name-path "UserAccount" \
     --relative-path "backend/models/user.py"
   ```

3. **Rename using built-in tool**:
   ```bash
   mcp__serena__rename_symbol \
     --name-path "UserAccount" \
     --relative-path "backend/models/user.py" \
     --new-name "Account"
   ```

**Result**: All references updated automatically ✅

---

## 🔄 Recipe 2: Extract Method from Long Function

**Goal**: Extract validation logic from `create_user()` into `validate_user_input()`

### Steps

1. **Read the function**:
   ```bash
   mcp__serena__find_symbol \
     --name-path-pattern "create_user" \
     --include-body true \
     --depth 0
   ```

2. **Extract lines 10-25 (validation logic)**:
   - Copy validation code from body
   - Create new function:
   ```bash
   mcp__serena__insert_before_symbol \
     --name-path "create_user" \
     --relative-path "backend/services/user.py" \
     --body "def validate_user_input(data: dict) -> dict:
       \"\"\"Validate user input data.\"\"\"
       # [paste validation code here]
       return data
   "
   ```

3. **Replace validation in original**:
   ```bash
   mcp__serena__replace_symbol_body \
     --name-path "create_user" \
     --relative-path "backend/services/user.py" \
     --body "def create_user(data: dict) -> User:
       data = validate_user_input(data)
       # [rest of function]
   "
   ```

**Result**: Cleaner, testable validation logic ✅

---

## 🔄 Recipe 3: Add Parameter to Multiple Functions

**Goal**: Add `user_id: str` parameter to all API endpoints

### Steps

1. **Find all endpoints**:
   ```bash
   mcp__serena__search_for_pattern \
     --substring-pattern '@app\.(get|post|put)' \
     --relative-path 'backend/api/' \
     --paths-include-glob '**/*.py'
   ```

2. **For each endpoint, read current signature**:
   ```bash
   mcp__serena__find_symbol \
     --name-path-pattern "get_portfolio" \
     --relative-path "backend/api/portfolio.py" \
     --include-body true
   ```

3. **Replace with new signature**:
   ```bash
   mcp__serena__replace_symbol_body \
     --name-path "get_portfolio" \
     --relative-path "backend/api/portfolio.py" \
     --body "def get_portfolio(user_id: str, portfolio_id: str = None):
       # Updated function body
   "
   ```

4. **Repeat for all endpoints**

**Tip**: Use TodoWrite to track which endpoints are updated

---

## 🔄 Recipe 4: Replace Implementation (Keep Interface)

**Goal**: Replace caching backend from Redis to in-memory

### Steps

1. **Find the cache class**:
   ```bash
   mcp__serena__find_symbol \
     --name-path-pattern "CacheService" \
     --include-body true \
     --depth 1  # Include methods
   ```

2. **Review method signatures** (keep interface same)

3. **Replace implementation**:
   ```bash
   mcp__serena__replace_symbol_body \
     --name-path "CacheService/get" \
     --relative-path "backend/services/cache.py" \
     --body "def get(self, key: str) -> Any:
       \"\"\"Get value from in-memory cache.\"\"\"
       return self._memory_cache.get(key)
   "
   ```

4. **Repeat for set(), delete(), clear() methods**

**Result**: Same API, different implementation ✅

---

## 🔄 Recipe 5: Move Function to Different Module

**Goal**: Move `calculate_returns()` from `utils.py` to `analytics.py`

### Steps

1. **Read the function**:
   ```bash
   mcp__serena__find_symbol \
     --name-path-pattern "calculate_returns" \
     --relative-path "backend/utils.py" \
     --include-body true
   ```

2. **Find all callers** (to update imports later):
   ```bash
   mcp__serena__find_referencing_symbols \
     --name-path "calculate_returns" \
     --relative-path "backend/utils.py"
   ```

3. **Insert into new location**:
   ```bash
   mcp__serena__insert_after_symbol \
     --name-path "calculate_volatility"  # Insert after this function \
     --relative-path "backend/analytics.py" \
     --body "def calculate_returns(prices: list[float]) -> list[float]:
       # [function body]
   "
   ```

4. **Delete from old location** (manual edit or replace with pass)

5. **Update imports in callers**:
   ```
   from backend.utils import calculate_returns
   → from backend.analytics import calculate_returns
   ```

**Result**: Better code organization ✅

---

## 🔄 Recipe 6: Add Decorator to Multiple Functions

**Goal**: Add `@require_auth` to all API endpoints

### Steps

1. **Find all endpoints**:
   ```bash
   mcp__serena__search_for_pattern \
     --substring-pattern 'def (get|post|put|delete)_.*\(' \
     --relative-path 'backend/api/' \
     --context-lines-before 2
   ```

2. **For each endpoint without @require_auth**:
   ```bash
   mcp__serena__find_symbol \
     --name-path-pattern "get_portfolio" \
     --include-body true
   ```

3. **Replace with decorated version**:
   ```bash
   mcp__serena__replace_symbol_body \
     --name-path "get_portfolio" \
     --relative-path "backend/api/portfolio.py" \
     --body "@require_auth
   def get_portfolio(user_id: str):
       # [function body]
   "
   ```

**Tip**: Check decorators already present to avoid duplicates

---

## 🔄 Recipe 7: Convert Class to Dataclass

**Goal**: Convert `User` class to use `@dataclass`

### Steps

1. **Read current class**:
   ```bash
   mcp__serena__find_symbol \
     --name-path-pattern "User" \
     --include-body true \
     --depth 1  # See __init__ method
   ```

2. **Extract field definitions from __init__**

3. **Replace class definition**:
   ```bash
   mcp__serena__replace_symbol_body \
     --name-path "User" \
     --relative-path "backend/models/user.py" \
     --body "@dataclass
   class User:
       id: str
       email: str
       created_at: datetime
       # No __init__ needed - auto-generated
   "
   ```

**Result**: Cleaner data class with auto __init__, __repr__, __eq__ ✅

---

## 🔄 Recipe 8: Add Error Handling to All Database Calls

**Goal**: Wrap all `session.execute()` calls with try/except

### Steps

1. **Find all database calls**:
   ```bash
   mcp__serena__search_for_pattern \
     --substring-pattern 'session\.execute\(' \
     --relative-path 'backend/' \
     --context-lines-before 5 \
     --context-lines-after 10
   ```

2. **For each function with db calls, read body**:
   ```bash
   mcp__serena__find_symbol \
     --name-path-pattern "get_user_by_email" \
     --include-body true
   ```

3. **Replace with error handling**:
   ```bash
   mcp__serena__replace_symbol_body \
     --name-path "get_user_by_email" \
     --relative-path "backend/services/user.py" \
     --body "def get_user_by_email(email: str) -> User | None:
       try:
           result = session.execute(...)
           return result.scalar_one_or_none()
       except SQLAlchemyError as e:
           logger.error(f\"Database error: {e}\")
           raise DatabaseException(\"Failed to fetch user\")
   "
   ```

**Result**: Robust error handling ✅

---

## 📊 Best Practices

### Before Refactoring

1. **Understand scope**: Use `find_referencing_symbols` to see impact
2. **Read tests**: Ensure you understand expected behavior
3. **Create Beads issue**: Track refactoring work (Issue-First pattern)

### During Refactoring

1. **One change at a time**: Rename OR move OR modify, not all at once
2. **Use TodoWrite**: Track multi-step refactorings
3. **Keep interface stable**: Change implementation, not API (when possible)
4. **Validate after each step**: Run tests, check imports

### After Refactoring

1. **Update tests**: Reflect new structure
2. **Update docs**: Keep documentation in sync
3. **Commit atomically**: One logical change per commit
4. **Check references**: No broken imports or undefined symbols

---

## 🎯 Common Patterns

### Pattern: Replace Across Multiple Files
```bash
# 1. Search for pattern
mcp__serena__search_for_pattern --substring-pattern "old_pattern"

# 2. For each file with matches
mcp__serena__find_symbol --name-path "symbol_name" --relative-path "file.py"

# 3. Replace
mcp__serena__replace_symbol_body --name-path "symbol_name" --new-body "..."
```

### Pattern: Extract then Inject
```bash
# 1. Read original
mcp__serena__find_symbol --name-path "original" --include-body true

# 2. Create extracted version
mcp__serena__insert_before_symbol --body "extracted function..."

# 3. Simplify original
mcp__serena__replace_symbol_body --body "simplified version..."
```

### Pattern: Incremental Migration
```bash
# 1. Create new implementation alongside old
mcp__serena__insert_after_symbol --body "new_implementation..."

# 2. Find all callers
mcp__serena__find_referencing_symbols --name-path "old_func"

# 3. Update callers one by one (or all at once)

# 4. Remove old implementation when safe
```

---

## 📚 Related

- **Common Searches**: [common-searches.md](common-searches.md) - Finding code to refactor
- **Symbol Operations**: [symbol-operations.md](symbol-operations.md) - Tool reference
- **Official Serena Docs**: https://github.com/oraios/serena
