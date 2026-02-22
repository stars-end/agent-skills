"""Tests for evaluator."""

import pytest
from pathlib import Path
from extended.gskill.lib.evaluator import SkillEvaluator, make_gepa_evaluator


def test_evaluator_signature():
    """Test evaluator has correct signature for GEPA."""
    evaluator = SkillEvaluator(Path("/tmp"))

    # Should have evaluate method
    assert hasattr(evaluator, "evaluate")


def test_gepa_evaluator_signature():
    """Test GEPA-compatible wrapper has correct signature."""
    evaluator = make_gepa_evaluator(Path("/tmp"))

    # Should accept (candidate, example=..., **kwargs)
    import inspect

    sig = inspect.signature(evaluator)
    params = list(sig.parameters.keys())

    assert "candidate" in params
    assert "example" in params


def test_evaluator_fails_fast_without_mutation(tmp_path):
    """Test evaluator fails fast when no mutation data available."""
    # Create minimal repo structure to avoid slow copytree
    (tmp_path / "foo.py").write_text("def foo(): pass")

    evaluator = SkillEvaluator(tmp_path)

    # Task without mutation data
    task = {
        "id": "test-1",
        "description": "Test task",
        "target_file": "foo.py",
        "test_command": "pytest foo.py",
    }

    score, side_info = evaluator.evaluate("test skill", task)

    # Should return 0 score with error message
    assert score == 0.0
    assert "No mutation data" in side_info
