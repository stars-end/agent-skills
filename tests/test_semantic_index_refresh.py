from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

import pytest

from scripts import semantic_index_refresh as sir


def write_config(tmp_path: Path) -> Path:
    cfg = {
        "schema_version": 1,
        "default_index_root": str(tmp_path / "indexes"),
        "allowlist": ["agent-skills"],
        "repositories": {
            "agent-skills": {
                "canonical_path": "/home/fengning/agent-skills",
                "source_remote": "git@github.com:stars-end/agent-skills.git",
                "source_branch": "master",
            }
        },
    }
    path = tmp_path / "repositories.json"
    path.write_text(json.dumps(cfg))
    return path


def test_allowlist_config_parsing(tmp_path: Path) -> None:
    cfg_path = write_config(tmp_path)
    cfg = sir.load_config(cfg_path)
    assert cfg["allowlist"] == ["agent-skills"]
    assert "agent-skills" in cfg["repositories"]


def test_unknown_repo_rejected(tmp_path: Path) -> None:
    cfg_path = write_config(tmp_path)
    rc = sir.main(["--repo-name", "unknown", "--config", str(cfg_path)])
    assert rc == 1


def test_dry_run_no_mutation(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    cfg_path = write_config(tmp_path)
    commands: list[list[str]] = []

    def fake_run(*args, **kwargs):  # type: ignore[no-untyped-def]
        commands.append(args[0])
        return subprocess.CompletedProcess(args[0], 0, "", "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    rc = sir.main(["--repo-name", "agent-skills", "--config", str(cfg_path), "--dry-run"])
    assert rc == 0
    assert commands == []
    out = capsys.readouterr().out
    assert "DRY RUN repo=agent-skills" in out
    assert not (tmp_path / "indexes").exists()


def test_lock_prevents_concurrent_run(tmp_path: Path) -> None:
    cfg_path = write_config(tmp_path)
    root = tmp_path / "indexes" / "agent-skills"
    root.mkdir(parents=True)
    lock_path = root / "refresh.lock"
    first = sir.lock_file(lock_path)
    try:
        with pytest.raises(sir.RefreshError):
            sir.lock_file(lock_path)
    finally:
        first.close()


def test_success_writes_schema_v1_state(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    cfg_path = write_config(tmp_path)
    index_root = tmp_path / "indexes"

    def fake_run(cmd, **kwargs):  # type: ignore[no-untyped-def]
        if cmd[:3] == ["git", "-C", str(index_root / "agent-skills" / "repo")]:
            if cmd[-1] == "HEAD":
                return subprocess.CompletedProcess(cmd, 0, "abc123\n", "")
            if cmd[-2:] == ["get-url", "origin"]:
                return subprocess.CompletedProcess(cmd, 0, "git@github.com:stars-end/agent-skills.git\n", "")
            return subprocess.CompletedProcess(cmd, 0, "", "")
        if cmd[:2] == ["git", "clone"]:
            (index_root / "agent-skills" / "repo").mkdir(parents=True, exist_ok=True)
            return subprocess.CompletedProcess(cmd, 0, "", "")
        if cmd[:2] == ["ccc", "doctor"]:
            return subprocess.CompletedProcess(
                cmd,
                0,
                "CocoIndex Code version: 0.2.31\nMatched files: 7\nEmbedding provider: sentence-transformers\nEmbedding model: Snowflake/snowflake-arctic-embed-xs\n",
                "",
            )
        if cmd[:2] == ["ccc", "index"]:
            project_dir = Path(kwargs["cwd"]) / ".cocoindex_code"
            project_dir.mkdir(parents=True, exist_ok=True)
            (project_dir / "target_sqlite.db").write_bytes(b"db")
            return subprocess.CompletedProcess(cmd, 0, "Total chunks: 11", "")
        return subprocess.CompletedProcess(cmd, 0, "", "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    rc = sir.main(["--repo-name", "agent-skills", "--config", str(cfg_path)])
    assert rc == 0
    state = json.loads((index_root / "agent-skills" / "state.json").read_text())
    assert state["schema_version"] == 1
    assert state["status"] == "success"
    assert state["repo_name"] == "agent-skills"
    assert state["indexed_head"] == "abc123"
    assert state["exit_code"] == 0
    assert state["db_bytes"] == 2
    assert state["matched_files"] == 7
    assert state["chunks"] == 11
    assert not (index_root / "agent-skills" / "refresh.lock").exists()


def test_failure_writes_non_ready_state_and_nonzero(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    cfg_path = write_config(tmp_path)
    index_root = tmp_path / "indexes"

    def fake_run(cmd, **kwargs):  # type: ignore[no-untyped-def]
        if cmd[:2] == ["git", "clone"]:
            (index_root / "agent-skills" / "repo").mkdir(parents=True, exist_ok=True)
            return subprocess.CompletedProcess(cmd, 0, "", "")
        if cmd[:2] == ["ccc", "index"]:
            return subprocess.CompletedProcess(cmd, 3, "", "index failed")
        return subprocess.CompletedProcess(cmd, 0, "abc123\n" if cmd[-1] == "HEAD" else "", "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    rc = sir.main(["--repo-name", "agent-skills", "--config", str(cfg_path)])
    assert rc != 0
    state = json.loads((index_root / "agent-skills" / "state.json").read_text())
    assert state["status"] == "failure"
    assert state["exit_code"] != 0
    assert "error" in state
    assert not (index_root / "agent-skills" / "refresh.lock").exists()


def test_missing_db_after_successful_status_is_failure(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    cfg_path = write_config(tmp_path)
    index_root = tmp_path / "indexes"

    def fake_run(cmd, **kwargs):  # type: ignore[no-untyped-def]
        if cmd[:2] == ["git", "clone"]:
            (index_root / "agent-skills" / "repo").mkdir(parents=True, exist_ok=True)
        return subprocess.CompletedProcess(cmd, 0, "abc123\n" if cmd[-1] == "HEAD" else "", "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    rc = sir.main(["--repo-name", "agent-skills", "--config", str(cfg_path)])
    assert rc != 0
    state = json.loads((index_root / "agent-skills" / "state.json").read_text())
    assert state["status"] == "failure"
    assert "index DB missing" in state["error"]


def test_timeout_records_failure(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    cfg_path = write_config(tmp_path)
    index_root = tmp_path / "indexes"

    def fake_run(cmd, **kwargs):  # type: ignore[no-untyped-def]
        if cmd[:2] == ["git", "clone"]:
            (index_root / "agent-skills" / "repo").mkdir(parents=True, exist_ok=True)
            return subprocess.CompletedProcess(cmd, 0, "", "")
        if cmd[:2] == ["ccc", "index"]:
            raise subprocess.TimeoutExpired(cmd, kwargs.get("timeout", 0))
        return subprocess.CompletedProcess(cmd, 0, "abc123\n" if cmd[-1] == "HEAD" else "", "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    rc = sir.main(["--repo-name", "agent-skills", "--config", str(cfg_path)])
    assert rc != 0
    state = json.loads((index_root / "agent-skills" / "state.json").read_text())
    assert state["status"] == "failure"
    assert "timeout" in state.get("error", "")


def test_index_root_override(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    cfg_path = write_config(tmp_path)
    custom_root = tmp_path / "custom-indexes"

    def fake_run(cmd, **kwargs):  # type: ignore[no-untyped-def]
        if cmd[:2] == ["git", "clone"]:
            (custom_root / "agent-skills" / "repo").mkdir(parents=True, exist_ok=True)
        if cmd[:2] == ["ccc", "index"]:
            project_dir = Path(kwargs["cwd"]) / ".cocoindex_code"
            project_dir.mkdir(parents=True, exist_ok=True)
            (project_dir / "target_sqlite.db").write_bytes(b"db")
        return subprocess.CompletedProcess(cmd, 0, "abc123\n" if cmd[-1] == "HEAD" else "", "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    rc = sir.main(["--repo-name", "agent-skills", "--config", str(cfg_path), "--index-root", str(custom_root)])
    assert rc == 0
    assert (custom_root / "agent-skills" / "state.json").exists()


def test_daemon_cleanup_attempted_and_scoped(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    cfg_path = write_config(tmp_path)
    index_root = tmp_path / "indexes"
    calls: list[tuple[list[str], dict[str, str] | None]] = []

    def fake_run(cmd, **kwargs):  # type: ignore[no-untyped-def]
        env = kwargs.get("env")
        calls.append((cmd, env))
        if cmd[:2] == ["git", "clone"]:
            (index_root / "agent-skills" / "repo").mkdir(parents=True, exist_ok=True)
        if cmd[:2] == ["ccc", "index"]:
            project_dir = Path(kwargs["cwd"]) / ".cocoindex_code"
            project_dir.mkdir(parents=True, exist_ok=True)
            (project_dir / "target_sqlite.db").write_bytes(b"db")
        if cmd[:2] == ["ccc", "daemon"]:
            return subprocess.CompletedProcess(cmd, 1, "", "stop failed")
        if cmd[:2] == ["pgrep", "-f"]:
            return subprocess.CompletedProcess(cmd, 0, "123\n", "")
        return subprocess.CompletedProcess(cmd, 0, "abc123\n" if cmd[-1] == "HEAD" else "", "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    rc = sir.main(["--repo-name", "agent-skills", "--config", str(cfg_path)])
    assert rc == 0
    coco = str(index_root / "agent-skills" / "coco-global")
    daemon_calls = [c for c in calls if c[0][:2] == ["ccc", "daemon"]]
    assert daemon_calls
    assert daemon_calls[0][1] is not None and daemon_calls[0][1]["COCOINDEX_CODE_DIR"] == coco
    assert any(c[0][:2] == ["pgrep", "-f"] and coco in c[0][2] for c in calls)


def test_no_canonical_clone_write_in_test_mode(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    cfg_path = write_config(tmp_path)
    home_before = Path("/home/fengning/agent-skills")
    assert home_before.exists()
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: subprocess.CompletedProcess(a[0], 0, "", ""))
    rc = sir.main(["--repo-name", "agent-skills", "--config", str(cfg_path), "--dry-run"])
    assert rc == 0
    assert not (home_before / "state.json").exists()
