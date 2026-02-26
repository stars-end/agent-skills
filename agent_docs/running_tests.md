# Running Tests

## Unit Tests
```bash
pytest tests/ -v
```

## Integration Tests
```bash
pytest tests/integration/ -v --cov
```

## Specific Test File
```bash
pytest tests/test_beads_workflow.py -v
```

## All Tests with Coverage
```bash
pytest tests/ --cov=lib --cov-report=html
```

## Pre-commit Checks
```bash
ruff check .
ruff format --check .
pytest tests/ -q
```
