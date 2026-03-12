"""Tests for the host-safe Railway Postgres wrapper."""

import os
import stat
import subprocess
from pathlib import Path


def write_executable(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def write_fake_railway(path: Path, log_path: Path) -> None:
    write_executable(
        path,
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                'cmd="${1:-}"',
                "shift || true",
                'if [[ "$cmd" == "status" ]]; then',
                "  exit 1",
                "fi",
                'if [[ "$cmd" == "run" ]]; then',
                '  echo "$*" >> "$DX_RAILWAY_POSTGRES_RUN_LOG"',
                '  service=""',
                '  while [[ $# -gt 0 ]]; do',
                '    if [[ "$1" == "-s" ]]; then',
                '      service="${2:-}"',
                "      shift 2",
                "      continue",
                "    fi",
                "    shift",
                "  done",
                '  if [[ "$service" == "Postgres" ]]; then',
                '    cat <<EOF',
                'DATABASE_URL=postgresql://dbuser:dbpass@postgres.railway.internal:5432/railway',
                'RAILWAY_TCP_PROXY_DOMAIN=maglev.proxy.rlwy.net',
                'RAILWAY_TCP_PROXY_PORT=40123',
                'EOF',
                '    exit 0',
                "  fi",
                '  if [[ "$service" == "backend" ]]; then',
                '    cat <<EOF',
                'DATABASE_URL=postgresql://appuser:apppass@postgres.railway.internal:5432/railway',
                'BACKEND_ONLY_VAR=backend-present',
                'EOF',
                '    exit 0',
                "  fi",
                "fi",
                "exit 0",
            ]
        ),
    )


def test_dx_railway_postgres_query_uses_proxy_url(tmp_path):
    script = (
        Path(__file__).parent.parent / "scripts" / "dx-railway-postgres.sh"
    )
    railway = tmp_path / "railway"
    psql = tmp_path / "psql"
    run_log = tmp_path / "railway-run.log"
    psql_log = tmp_path / "psql.log"
    repo_root = tmp_path / "repo"

    repo_root.mkdir()
    (repo_root / "backend").mkdir()
    write_fake_railway(railway, run_log)
    write_executable(
        psql,
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                'printf "%s\\n" "$*" > "$DX_RAILWAY_POSTGRES_PSQL_LOG"',
                "exit 0",
            ]
        ),
    )

    dx_dir = repo_root / ".dx"
    dx_dir.mkdir()
    (dx_dir / "railway-context.env").write_text(
        "\n".join(
            [
                "RAILWAY_PROJECT_ID=test-project",
                "RAILWAY_ENVIRONMENT=dev",
            ]
        )
    )

    env = os.environ.copy()
    env["PATH"] = f"{tmp_path}:{env['PATH']}"
    env["RAILWAY_API_TOKEN"] = "test-token"
    env["DX_RAILWAY_POSTGRES_RUN_LOG"] = str(run_log)
    env["DX_RAILWAY_POSTGRES_PSQL_LOG"] = str(psql_log)

    result = subprocess.run(
        [
            str(script),
            "--repo-root",
            str(repo_root),
            "query",
            "--sql",
            "SELECT 1 AS ok",
        ],
        cwd=repo_root,
        capture_output=True,
        text=True,
        env=env,
    )

    assert result.returncode == 0, result.stderr
    assert "-p test-project -e dev -s Postgres -- bash -lc env" in run_log.read_text()
    psql_args = psql_log.read_text()
    assert "postgresql://dbuser:dbpass@maglev.proxy.rlwy.net:40123/railway" in psql_args
    assert "-c SELECT 1 AS ok" in psql_args


def test_dx_railway_postgres_backend_python_rewrites_database_url(tmp_path):
    script = (
        Path(__file__).parent.parent / "scripts" / "dx-railway-postgres.sh"
    )
    railway = tmp_path / "railway"
    run_log = tmp_path / "railway-run.log"
    repo_root = tmp_path / "repo"

    repo_root.mkdir()
    (repo_root / "backend").mkdir()
    write_fake_railway(railway, run_log)

    dx_dir = repo_root / ".dx"
    dx_dir.mkdir()
    (dx_dir / "railway-context.env").write_text(
        "\n".join(
            [
                "RAILWAY_PROJECT_ID=test-project",
                "RAILWAY_ENVIRONMENT=dev",
            ]
        )
    )

    env = os.environ.copy()
    env["PATH"] = f"{tmp_path}:{env['PATH']}"
    env["RAILWAY_API_TOKEN"] = "test-token"
    env["DX_RAILWAY_POSTGRES_RUN_LOG"] = str(run_log)

    result = subprocess.run(
        [
            str(script),
            "--repo-root",
            str(repo_root),
            "backend-python",
            "--",
            "python3",
            "-c",
            "import os; print(os.environ['DATABASE_URL']); print(os.environ['BACKEND_ONLY_VAR'])",
        ],
        cwd=repo_root,
        capture_output=True,
        text=True,
        env=env,
    )

    assert result.returncode == 0, result.stderr
    lines = result.stdout.strip().splitlines()
    assert lines[0] == "postgresql://appuser:apppass@maglev.proxy.rlwy.net:40123/railway"
    assert lines[1] == "backend-present"
    logged = run_log.read_text()
    assert "-p test-project -e dev -s backend -- bash -lc env" in logged
    assert "-p test-project -e dev -s Postgres -- bash -lc env" in logged
