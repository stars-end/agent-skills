"""Tests for dx-railway-run worktree fallback behavior."""

import os
import stat
import subprocess
from pathlib import Path


def write_executable(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def write_script_fixture(tmp_path: Path, script_name: str) -> Path:
    scripts_dir = Path(__file__).parent.parent / "scripts"
    script = tmp_path / script_name
    script.write_text((scripts_dir / script_name).read_text())
    script.chmod(script.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    lib_dir = tmp_path / "lib"
    lib_dir.mkdir(exist_ok=True)
    (lib_dir / "dx-auth.sh").write_text((scripts_dir / "lib" / "dx-auth.sh").read_text())
    return script


def test_dx_railway_run_uses_linked_context(tmp_path):
    script = write_script_fixture(tmp_path, "dx-railway-run.sh")

    railway = tmp_path / "railway"
    run_log = tmp_path / "run.log"
    write_executable(
        railway,
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                'cmd="${1:-}"',
                "shift || true",
                'if [[ "$cmd" == "status" ]]; then',
                '  [[ "${RAILWAY_MOCK_LINKED:-0}" == "1" ]] && exit 0 || exit 1',
                "fi",
                'if [[ "$cmd" == "run" ]]; then',
                '  echo "$*" >> "$DX_RAILWAY_RUN_LOG"',
                "  exit 0",
                "fi",
                "exit 0",
            ]
        ),
    )

    env = os.environ.copy()
    env["PATH"] = f"{tmp_path}:{env['PATH']}"
    env["RAILWAY_MOCK_LINKED"] = "1"
    env["DX_RAILWAY_RUN_LOG"] = str(run_log)

    result = subprocess.run(
        [str(script), "--", "make", "dev"], capture_output=True, text=True, env=env
    )
    assert result.returncode == 0
    assert "-- make dev" in run_log.read_text()


def test_dx_railway_run_uses_seeded_context_when_unlinked(tmp_path):
    script = write_script_fixture(tmp_path, "dx-railway-run.sh")

    railway = tmp_path / "railway"
    run_log = tmp_path / "run.log"
    write_executable(
        railway,
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
                '  echo "$*" >> "$DX_RAILWAY_RUN_LOG"',
                "  exit 0",
                "fi",
                "exit 0",
            ]
        ),
    )

    dx_dir = tmp_path / ".dx"
    dx_dir.mkdir(parents=True, exist_ok=True)
    (dx_dir / "railway-context.env").write_text(
        "\n".join(
            [
                "RAILWAY_PROJECT_ID=test-project-id",
                "RAILWAY_ENVIRONMENT=dev",
                "RAILWAY_SERVICE=backend",
            ]
        )
    )

    env = os.environ.copy()
    env["PATH"] = f"{tmp_path}:{env['PATH']}"
    env["DX_RAILWAY_RUN_LOG"] = str(run_log)

    result = subprocess.run(
        [str(script), "--", "make", "verify-pipeline"],
        capture_output=True,
        text=True,
        cwd=tmp_path,
        env=env,
    )
    assert result.returncode == 0
    logged = run_log.read_text()
    assert "-p test-project-id -e dev -s backend -- make verify-pipeline" in logged


def test_dx_railway_run_honors_service_override_even_when_linked(tmp_path):
    script = write_script_fixture(tmp_path, "dx-railway-run.sh")

    railway = tmp_path / "railway"
    run_log = tmp_path / "run.log"
    write_executable(
        railway,
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                'cmd="${1:-}"',
                "shift || true",
                'if [[ "$cmd" == "status" ]]; then',
                '  [[ "${RAILWAY_MOCK_LINKED:-0}" == "1" ]] && exit 0 || exit 1',
                "fi",
                'if [[ "$cmd" == "run" ]]; then',
                '  echo "$*" >> "$DX_RAILWAY_RUN_LOG"',
                "  exit 0",
                "fi",
                "exit 0",
            ]
        ),
    )

    env = os.environ.copy()
    env["PATH"] = f"{tmp_path}:{env['PATH']}"
    env["RAILWAY_MOCK_LINKED"] = "1"
    env["DX_RAILWAY_RUN_LOG"] = str(run_log)
    env["DX_RAILWAY_PROJECT_ID"] = "project-123"

    result = subprocess.run(
        [str(script), "--service", "backend", "--", "python3", "-V"],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0
    assert "-p project-123 -e dev -s backend -- python3 -V" in run_log.read_text()


def test_dx_railway_run_executes_directly_in_railway_shell(tmp_path):
    script = write_script_fixture(tmp_path, "dx-railway-run.sh")

    railway = tmp_path / "railway"
    write_executable(
        railway,
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                "exit 0",
            ]
        ),
    )

    env = os.environ.copy()
    env["PATH"] = f"{tmp_path}:{env['PATH']}"
    env["RAILWAY_ENVIRONMENT"] = "dev"

    result = subprocess.run(
        [str(script), "--", "python3", "-c", "print('direct-ok')"],
        capture_output=True,
        text=True,
        env=env,
    )
    assert result.returncode == 0
    assert "direct-ok" in result.stdout
