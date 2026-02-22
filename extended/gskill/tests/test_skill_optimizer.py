"""Tests for skill optimizer."""

import pytest
from pathlib import Path
from extended.gskill.lib.skill_optimizer import SkillOptimizer


def test_optimizer_init():
    """Test optimizer can be initialized."""
    opt = SkillOptimizer(Path("/tmp"))
    assert opt is not None
    assert opt.max_metric_calls == 100


def test_optimizer_has_template_path():
    """Test optimizer has reflection template path."""
    opt = SkillOptimizer(Path("/tmp"))
    assert opt.reflection_template_path is not None


def test_load_tasks_empty_file(tmp_path):
    """Test loading tasks from empty file."""
    opt = SkillOptimizer(Path("/tmp"))

    tasks_file = tmp_path / "tasks.jsonl"
    tasks_file.write_text("")

    tasks = opt._load_tasks(tasks_file)
    assert tasks == []


def test_load_tasks_valid_file(tmp_path):
    """Test loading tasks from valid JSONL."""
    opt = SkillOptimizer(Path("/tmp"))

    tasks_file = tmp_path / "tasks.jsonl"
    tasks_file.write_text(
        '{"id": "1", "target_file": "foo.py"}\n{"id": "2", "target_file": "bar.py"}\n'
    )

    tasks = opt._load_tasks(tasks_file)
    assert len(tasks) == 2
    assert tasks[0]["id"] == "1"
