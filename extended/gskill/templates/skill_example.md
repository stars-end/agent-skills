# Repository-Specific Skills (Example Format)

This is an example of a well-structured skill file.

## Testing Patterns

1) Run tests early and iterate from failures
- Start broad when feasible: `pytest tests/`
- Narrow quickly:
  - single file: `pytest tests/test_file.py`
  - single test: `pytest tests/test_file.py -k test_name -v`
- For panics: follow the stack trace top frame in repo code first
- For mismatches: use "expected vs got" to locate the producing function

## Code Patterns

2) Make minimal, reviewable changes and verify continuously
- Change one behavior at a time; rerun the smallest reproducing test after each change
- Add focused unit tests when coverage is missing
- Avoid scratch files in repo root

3) Always check for NULL before aggregation
- Pattern: `COALESCE(column, 0)` or `column IS NOT NULL`
- Failure: NULL propagates, crashes downstream

4) Use idempotent upserts for sync operations
- Pattern: `ON CONFLICT (id) DO UPDATE`
- Failure: Duplicate rows on retry
