from __future__ import annotations

import fcntl
import os
import subprocess
from pathlib import Path

from tests.semantic_index_fixtures import init_git_repo, sh, write_ccc_stub, write_config, write_state


def run_tool(
    repo_root: Path,
    args: list[str],
    ccc_bin: Path,
    config: Path,
    *,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    cmd = [
        "python3",
        str(repo_root / "scripts/semantic-search"),
        "--ccc-bin",
        str(ccc_bin),
        "--config",
        str(config),
        *args,
    ]
    run_env = dict(os.environ)
    if env:
        run_env.update(env)
    return subprocess.run(cmd, cwd=str(repo_root), env=run_env, capture_output=True, text=True, check=False)


def test_status_missing(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    canonical = tmp_path / "agent-skills"
    init_git_repo(canonical)
    config = tmp_path / "repositories.json"
    write_config(config, "agent-skills", canonical, tmp_path / "indexes" / "agent-skills")
    ccc = tmp_path / "ccc"
    write_ccc_stub(ccc, "#!/usr/bin/env bash\nexit 0\n")
    cp = run_tool(repo_root, ["status", "--repo", str(canonical)], ccc, config)
    assert cp.stdout.strip() == "missing"


def test_status_indexing_via_lock(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    canonical = tmp_path / "agent-skills"
    head = init_git_repo(canonical)
    index_root = tmp_path / "indexes" / "agent-skills"
    write_state(index_root, repo_name="agent-skills", indexed_head=head)
    lock_path = index_root / "refresh.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock_handle = lock_path.open("a+")
    fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    config = tmp_path / "repositories.json"
    write_config(config, "agent-skills", canonical, index_root)
    ccc = tmp_path / "ccc"
    write_ccc_stub(ccc, "#!/usr/bin/env bash\nexit 0\n")
    try:
        cp = run_tool(repo_root, ["status", "--repo", str(canonical)], ccc, config)
        assert cp.stdout.strip() == "indexing"
    finally:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
        lock_handle.close()


def test_stale_lock_file_does_not_block_ready_status(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    canonical = tmp_path / "agent-skills"
    head = init_git_repo(canonical)
    index_root = tmp_path / "indexes" / "agent-skills"
    write_state(index_root, repo_name="agent-skills", indexed_head=head)
    (index_root / "refresh.lock").write_text("", encoding="utf-8")
    config = tmp_path / "repositories.json"
    write_config(config, "agent-skills", canonical, index_root)
    ccc = tmp_path / "ccc"
    write_ccc_stub(ccc, "#!/usr/bin/env bash\nexit 0\n")
    cp = run_tool(repo_root, ["status", "--repo", str(canonical)], ccc, config)
    assert cp.stdout.strip() == "ready"


def test_status_stale_head_mismatch(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    canonical = tmp_path / "agent-skills"
    old_head = init_git_repo(canonical)
    (canonical / "a.txt").write_text("x\n", encoding="utf-8")
    sh(["git", "add", "a.txt"], cwd=canonical)
    sh(["git", "commit", "-m", "next"], cwd=canonical)
    index_root = tmp_path / "indexes" / "agent-skills"
    write_state(index_root, repo_name="agent-skills", indexed_head=old_head)
    config = tmp_path / "repositories.json"
    write_config(config, "agent-skills", canonical, index_root)
    ccc = tmp_path / "ccc"
    write_ccc_stub(ccc, "#!/usr/bin/env bash\nexit 0\n")
    cp = run_tool(repo_root, ["status", "--repo", str(canonical)], ccc, config)
    assert cp.stdout.strip() == "stale"


def test_status_ready(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    canonical = tmp_path / "agent-skills"
    head = init_git_repo(canonical)
    index_root = tmp_path / "indexes" / "agent-skills"
    write_state(index_root, repo_name="agent-skills", indexed_head=head)
    config = tmp_path / "repositories.json"
    write_config(config, "agent-skills", canonical, index_root)
    ccc = tmp_path / "ccc"
    write_ccc_stub(
        ccc,
        "#!/usr/bin/env bash\n"
        "if [ \"$1\" = \"status\" ]; then exit 0; fi\n"
        "if [ \"$1\" = \"search\" ]; then echo \"hit\"; exit 0; fi\n"
        "exit 1\n",
    )
    cp = run_tool(repo_root, ["status", "--repo", str(canonical)], ccc, config)
    assert cp.stdout.strip() == "ready"


def test_unknown_schema_non_ready(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    canonical = tmp_path / "agent-skills"
    head = init_git_repo(canonical)
    index_root = tmp_path / "indexes" / "agent-skills"
    write_state(index_root, repo_name="agent-skills", indexed_head=head, schema_version=99)
    config = tmp_path / "repositories.json"
    write_config(config, "agent-skills", canonical, index_root)
    ccc = tmp_path / "ccc"
    write_ccc_stub(ccc, "#!/usr/bin/env bash\nexit 0\n")
    cp = run_tool(repo_root, ["status", "--repo", str(canonical)], ccc, config)
    assert cp.stdout.strip() == "stale"


def test_exact_worktree_resolver_and_unknown_fail_closed(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    canonical = tmp_path / "agent-skills"
    head = init_git_repo(canonical)
    index_root = tmp_path / "indexes" / "agent-skills"
    write_state(index_root, repo_name="agent-skills", indexed_head=head)
    config = tmp_path / "repositories.json"
    write_config(config, "agent-skills", canonical, index_root)
    ccc = tmp_path / "ccc"
    write_ccc_stub(ccc, "#!/usr/bin/env bash\nexit 0\n")

    known_worktree = Path("/tmp/agents/bd-abc1/agent-skills")
    if known_worktree.exists():
        sh(["rm", "-rf", str(known_worktree)])
    known_worktree.parent.mkdir(parents=True, exist_ok=True)
    sh(["git", "clone", "--no-hardlinks", str(canonical), str(known_worktree)])
    cp1 = run_tool(repo_root, ["status", "--repo", str(known_worktree)], ccc, config)
    assert cp1.stdout.strip() == "ready"

    unknown_worktree = Path("/tmp/agents/bd-abc1/unknown-repo")
    unknown_worktree.mkdir(parents=True, exist_ok=True)
    cp2 = run_tool(repo_root, ["status", "--repo", str(unknown_worktree)], ccc, config)
    assert cp2.stdout.strip() == "missing"


def test_dirty_worktree_is_stale(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    canonical = tmp_path / "agent-skills"
    head = init_git_repo(canonical)
    index_root = tmp_path / "indexes" / "agent-skills"
    write_state(index_root, repo_name="agent-skills", indexed_head=head)
    config = tmp_path / "repositories.json"
    write_config(config, "agent-skills", canonical, index_root)
    ccc = tmp_path / "ccc"
    write_ccc_stub(ccc, "#!/usr/bin/env bash\nexit 0\n")

    wt = Path("/tmp/agents/bd-dirty1/agent-skills")
    if wt.exists():
        sh(["rm", "-rf", str(wt)])
    wt.parent.mkdir(parents=True, exist_ok=True)
    sh(["git", "clone", "--no-hardlinks", str(canonical), str(wt)])
    (wt / "README.md").write_text("dirty\n", encoding="utf-8")
    cp = run_tool(repo_root, ["status", "--repo", str(wt)], ccc, config)
    assert cp.stdout.strip() == "stale"


def test_query_never_invokes_raw_ccc_and_ready_search_has_limit(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    canonical = tmp_path / "agent-skills"
    head = init_git_repo(canonical)
    index_root = tmp_path / "indexes" / "agent-skills"
    write_state(index_root, repo_name="agent-skills", indexed_head=head)
    config = tmp_path / "repositories.json"
    write_config(config, "agent-skills", canonical, index_root)
    log = tmp_path / "ccc.log"
    ccc = tmp_path / "ccc"
    write_ccc_stub(
        ccc,
        "#!/usr/bin/env bash\n"
        f"echo raw-ccc:$@ >> {log}\n"
        "exit 99\n",
    )
    runner = tmp_path / "query-runner"
    write_ccc_stub(
        runner,
        "#!/usr/bin/env bash\n"
        f"echo runner:$@ >> {log}\n"
        f"echo runner-cwd:$(pwd) >> {log}\n"
        f"echo runner-coco:${{COCOINDEX_CODE_DIR:-}} >> {log}\n"
        "echo 'result'\n",
    )
    cp = run_tool(
        repo_root,
        ["query", "--repo", str(canonical), "needle", "--limit", "3"],
        ccc,
        config,
        env={"SEMANTIC_SEARCH_QUERY_RUNNER": str(runner)},
    )
    assert cp.returncode == 0
    assert "result" in cp.stdout
    calls = log.read_text(encoding="utf-8")
    assert "raw-ccc:" not in calls
    assert "runner:--db" in calls
    assert "--query needle --limit 3" in calls
    assert f"runner-cwd:{index_root / 'repo'}" in calls
    assert f"runner-coco:{index_root / 'coco-global'}" in calls


def test_query_fallback_for_non_ready_and_timeout(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    canonical = tmp_path / "agent-skills"
    head = init_git_repo(canonical)
    index_root = tmp_path / "indexes" / "agent-skills"
    write_state(index_root, repo_name="agent-skills", indexed_head=head)
    config = tmp_path / "repositories.json"
    write_config(config, "agent-skills", canonical, index_root)
    ccc = tmp_path / "ccc"
    write_ccc_stub(ccc, "#!/usr/bin/env bash\nexit 99\n")
    runner = tmp_path / "query-runner"
    write_ccc_stub(runner, "#!/usr/bin/env bash\nsleep 2; echo late\n")
    # stale path
    (canonical / "a.txt").write_text("x\n", encoding="utf-8")
    sh(["git", "add", "a.txt"], cwd=canonical)
    sh(["git", "commit", "-m", "next"], cwd=canonical)
    cp1 = run_tool(repo_root, ["query", "--repo", str(canonical), "q"], ccc, config)
    assert cp1.returncode != 0
    assert cp1.stderr.strip() == "semantic index unavailable; use rg."

    # ready with timeout search path
    canonical2 = tmp_path / "llm-common"
    head2 = init_git_repo(canonical2)
    idx2 = tmp_path / "indexes" / "llm-common"
    write_state(idx2, repo_name="llm-common", indexed_head=head2)
    config2 = tmp_path / "repositories2.json"
    write_config(config2, "llm-common", canonical2, idx2)
    cp2 = run_tool(
        repo_root,
        ["--search-timeout", "1", "query", "--repo", str(canonical2), "q"],
        ccc,
        config2,
        env={"SEMANTIC_SEARCH_QUERY_RUNNER": str(runner)},
    )
    assert cp2.returncode != 0
    assert cp2.stderr.strip().endswith("semantic index unavailable; use rg.")


def test_status_never_invokes_raw_ccc(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    canonical = tmp_path / "agent-skills"
    head = init_git_repo(canonical)
    index_root = tmp_path / "indexes" / "agent-skills"
    write_state(index_root, repo_name="agent-skills", indexed_head=head)
    config = tmp_path / "repositories.json"
    write_config(config, "agent-skills", canonical, index_root)
    log = tmp_path / "ccc.log"
    ccc = tmp_path / "ccc"
    write_ccc_stub(ccc, "#!/usr/bin/env bash\n" f"echo raw-ccc:$@ >> {log}\n" "exit 99\n")

    cp = run_tool(repo_root, ["status", "--repo", str(canonical)], ccc, config)

    assert cp.returncode == 0
    assert cp.stdout.strip() == "ready"
    assert not log.exists()
