from __future__ import annotations

import json
import subprocess
from pathlib import Path


def sh(cmd: list[str], cwd: Path | None = None) -> None:
    subprocess.run(cmd, cwd=str(cwd) if cwd else None, check=True, capture_output=True, text=True)


def init_git_repo(path: Path) -> str:
    path.mkdir(parents=True, exist_ok=True)
    sh(["git", "init"], cwd=path)
    sh(["git", "config", "user.email", "test@example.com"], cwd=path)
    sh(["git", "config", "user.name", "Test User"], cwd=path)
    (path / "README.md").write_text("hello\n", encoding="utf-8")
    sh(["git", "add", "README.md"], cwd=path)
    sh(["git", "commit", "-m", "init"], cwd=path)
    cp = subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"], check=True, capture_output=True, text=True)
    return cp.stdout.strip()


def write_config(config_path: Path, repo_name: str, canonical_path: Path, index_root: Path) -> None:
    config_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": 1,
        "default_index_root": str(index_root.parent),
        "allowlist": [repo_name],
        "repositories": {
            repo_name: {
                "canonical_path": str(canonical_path),
                "source_branch": "master",
            }
        }
    }
    config_path.write_text(json.dumps(payload), encoding="utf-8")


def write_state(index_root: Path, *, repo_name: str, indexed_head: str, schema_version: int = 1, status: str = "success") -> None:
    index_root.mkdir(parents=True, exist_ok=True)
    project_dir = index_root / "repo" / ".cocoindex_code"
    project_dir.mkdir(parents=True, exist_ok=True)
    (index_root / "coco-global").mkdir(parents=True, exist_ok=True)
    state = {
        "schema_version": schema_version,
        "repo_name": repo_name,
        "indexed_head": indexed_head,
        "status": status,
    }
    (index_root / "state.json").write_text(json.dumps(state), encoding="utf-8")
    (project_dir / "target_sqlite.db").write_bytes(b"db")
    (project_dir / "settings.yml").write_text("ok: true\n", encoding="utf-8")


def write_ccc_stub(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(0o755)
