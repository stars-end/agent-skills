"""Tests for task generator."""
import pytest
from pathlib import Path
from extended.gskill.lib.task_generator import TaskGenerator


def test_discover_targets_with_explicit_patterns(tmp_path):
    """Test discovery with explicit patterns set BEFORE discover_targets()."""
    # Create sample repo
    (tmp_path / "services").mkdir()
    (tmp_path / "services" / "foo.py").write_text("def bar(): pass")
    (tmp_path / "migrations").mkdir()
    (tmp_path / "migrations" / "001.py").write_text("# migration")

    gen = TaskGenerator(tmp_path, language="python")

    # MUST set patterns BEFORE discover_targets
    gen.set_target_patterns(["services/*.py"])
    gen.set_exclude_patterns(["*/migrations/*"])

    targets = gen.discover_targets()

    assert len(targets) >= 1
    assert any("foo.py" in str(t) for t in targets)
    # Verify migration excluded
    assert not any("migrations" in str(t) for t in targets)


def test_discover_targets_empty_patterns(tmp_path):
    """Test that generator returns empty when no patterns set."""
    (tmp_path / "services").mkdir()
    (tmp_path / "services" / "foo.py").write_text("def bar(): pass")

    gen = TaskGenerator(tmp_path, language="python")
    # Don't set patterns

    targets = gen.discover_targets()
    # Should return empty list, not crash
    assert isinstance(targets, list)


def test_exclude_glob_patterns_work(tmp_path):
    """Verify glob patterns actually exclude matching files."""
    (tmp_path / "backend").mkdir()
    (tmp_path / "backend" / "migrations").mkdir()
    (tmp_path / "backend" / "services").mkdir()
    (tmp_path / "backend" / "migrations" / "001.py").write_text("# migration")
    (tmp_path / "backend" / "services" / "real.py").write_text("def foo(): pass")

    gen = TaskGenerator(tmp_path, language="python")
    gen.set_target_patterns(["backend/**/*.py"])
    gen.set_exclude_patterns(["*/migrations/*"])

    targets = gen.discover_targets()

    # Should include services, exclude migrations
    paths = [str(t) for t in targets]
    assert any("real.py" in p for p in paths)
    assert not any("migrations" in p for p in paths)


def test_task_to_dict():
    """Test Task serialization."""
    from extended.gskill.lib.task_generator import Task

    task = Task(
        id="test_1",
        description="Fix bug",
        repo_path="/tmp/repo",
        target_file="foo.py",
        test_command="pytest foo.py",
        setup_commands=[],
        mutation_patch="--- a/foo.py\n+++ b/foo.py",
        mutated_code="def foo(): return 2",
    )

    d = task.to_dict()
    assert d["id"] == "test_1"
    assert d["target_file"] == "foo.py"
    assert "mutation_patch" in d
    assert "mutated_code" in d
