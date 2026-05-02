from __future__ import annotations

import importlib.util
import json
import os
import stat
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parent.parent / "scripts" / "semantic_search.py"
SPEC = importlib.util.spec_from_file_location("semantic_search", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
semantic_search = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(semantic_search)


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


def _init_repo(repo: Path) -> None:
    os.system(f'git -C "{repo}" init -q')
    os.system(f'git -C "{repo}" config user.email "tests@example.com"')
    os.system(f'git -C "{repo}" config user.name "Tests"')
    tracked = repo / "tracked.txt"
    tracked.write_text("base\n", encoding="utf-8")
    os.system(f'git -C "{repo}" add tracked.txt')
    os.system(f'git -C "{repo}" commit -q -m "init"')


def _prepare_index(repo: Path) -> Path:
    index_dir = repo / ".cocoindex_code"
    index_dir.mkdir(parents=True, exist_ok=True)
    (index_dir / "settings.yml").write_text("x: 1\n", encoding="utf-8")
    target_db = index_dir / "target_sqlite.db"
    target_db.write_text("db", encoding="utf-8")
    return target_db


def _stub_ccc(path: Path) -> None:
    _write_executable(
        path,
        """#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

log_path = os.environ.get("CCC_LOG")
if log_path:
    with Path(log_path).open("a", encoding="utf-8") as f:
        f.write(" ".join(sys.argv[1:]) + "\\n")

if sys.argv[1] == "status":
    print(os.environ.get("CCC_STATUS_OUTPUT", "ready"))
    sys.exit(0)

if sys.argv[1] == "search":
    print(json.dumps({"query": sys.argv[2], "limit": sys.argv[4]}))
    sys.exit(0)

sys.exit(0)
""",
    )


def test_status_missing(tmp_path, capsys):
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    ccc = tmp_path / "ccc"
    _stub_ccc(ccc)

    rc = semantic_search.main(["--ccc-bin", str(ccc), "status", "--repo", str(repo)])
    out = capsys.readouterr().out.strip()

    assert rc == 0
    assert out == "missing"


def test_status_indexing(tmp_path, monkeypatch, capsys):
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _prepare_index(repo)
    ccc = tmp_path / "ccc"
    _stub_ccc(ccc)
    monkeypatch.setenv("CCC_STATUS_OUTPUT", "Indexing in progress: 10 files listed")

    rc = semantic_search.main(["--ccc-bin", str(ccc), "status", "--repo", str(repo)])
    out = capsys.readouterr().out.strip()

    assert rc == 0
    assert out == "indexing"


def test_status_stale_when_repo_dirty(tmp_path, monkeypatch, capsys):
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _prepare_index(repo)
    (repo / "tracked.txt").write_text("dirty\n", encoding="utf-8")
    ccc = tmp_path / "ccc"
    _stub_ccc(ccc)
    monkeypatch.setenv("CCC_STATUS_OUTPUT", "ready")

    rc = semantic_search.main(["--ccc-bin", str(ccc), "status", "--repo", str(repo)])
    out = capsys.readouterr().out.strip()

    assert rc == 0
    assert out == "stale"


def test_status_missing_when_ccc_unavailable(tmp_path, capsys):
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _prepare_index(repo)

    rc = semantic_search.main(
        ["--ccc-bin", str(tmp_path / "no-such-ccc"), "status", "--repo", str(repo)]
    )
    out = capsys.readouterr().out.strip()

    assert rc == 0
    assert out == "missing"


def test_query_non_ready_does_not_call_search(tmp_path, monkeypatch, capsys):
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _prepare_index(repo)
    ccc = tmp_path / "ccc"
    _stub_ccc(ccc)
    log = tmp_path / "ccc.log"
    monkeypatch.setenv("CCC_LOG", str(log))
    monkeypatch.setenv("CCC_STATUS_OUTPUT", "Indexing in progress")

    rc = semantic_search.main(
        ["--ccc-bin", str(ccc), "query", "--repo", str(repo), "where is loop state machine"]
    )
    captured = capsys.readouterr()
    logged = log.read_text(encoding="utf-8")

    assert rc == 2
    assert semantic_search.UNAVAILABLE_MESSAGE in captured.err
    assert "status" in logged
    assert "search" not in logged


def test_query_ccc_unavailable_falls_back_cleanly(tmp_path, capsys):
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _prepare_index(repo)

    rc = semantic_search.main(
        [
            "--ccc-bin",
            str(tmp_path / "no-such-ccc"),
            "query",
            "--repo",
            str(repo),
            "any query",
        ]
    )
    captured = capsys.readouterr()

    assert rc == 2
    assert semantic_search.UNAVAILABLE_MESSAGE in captured.err


def test_query_ready_runs_bounded_search_with_limit(tmp_path, monkeypatch, capsys):
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    target_db = _prepare_index(repo)
    ccc = tmp_path / "ccc"
    _stub_ccc(ccc)
    log = tmp_path / "ccc.log"
    monkeypatch.setenv("CCC_LOG", str(log))
    monkeypatch.setenv("CCC_STATUS_OUTPUT", "ready")
    # Make index definitely newer than git refs.
    now = os.path.getmtime(target_db)
    os.utime(target_db, (now + 120, now + 120))

    rc = semantic_search.main(
        [
            "--ccc-bin",
            str(ccc),
            "--search-timeout",
            "7",
            "query",
            "--repo",
            str(repo),
            "find dx-loop status polling",
            "--limit",
            "3",
        ]
    )
    captured = capsys.readouterr()
    payload = json.loads(captured.out.strip())
    logged = log.read_text(encoding="utf-8")

    assert rc == 0
    assert payload == {"query": "find dx-loop status polling", "limit": "3"}
    assert "status" in logged
    assert "search find dx-loop status polling --limit 3" in logged
