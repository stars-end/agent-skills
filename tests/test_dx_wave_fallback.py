"""Tests for dx-wave batch fallback behavior when dx-batch is unavailable."""

import os
import stat
import subprocess
from pathlib import Path


def write_executable(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def test_dx_wave_batch_fallback_to_dx_runner(tmp_path):
    script_src = Path(__file__).parent.parent / "scripts" / "dx-wave"
    wave_script = tmp_path / "dx-wave"
    wave_script.write_text(script_src.read_text())
    wave_script.chmod(
        wave_script.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
    )

    runner_script = tmp_path / "dx-runner"
    runner_log = tmp_path / "runner.log"
    write_executable(
        runner_script,
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "set -euo pipefail",
                "echo \"$*\" >> \"$DX_WAVE_TEST_RUNNER_LOG\"",
            ]
        ),
    )

    prompt_file = tmp_path / "prompt.txt"
    prompt_file.write_text("test prompt")

    env = os.environ.copy()
    env["DX_WAVE_TEST_RUNNER_LOG"] = str(runner_log)
    env["DX_WAVE_PROFILE"] = "opencode-prod"
    # Ensure command -v dx-batch does not find a binary.
    env["PATH"] = "/usr/bin:/bin"

    result = subprocess.run(
        [
            str(wave_script),
            "batch-start",
            "--items",
            "bd-wave.1,bd-wave.2",
            "--prompt-file",
            str(prompt_file),
        ],
        capture_output=True,
        text=True,
        env=env,
    )

    assert result.returncode == 0
    assert "WARN_CODE=dx_batch_unavailable_fallback_runner" in result.stderr

    calls = runner_log.read_text().strip().splitlines()
    assert len(calls) == 2
    assert "--beads bd-wave.1" in calls[0]
    assert "--beads bd-wave.2" in calls[1]
    assert "--profile opencode-prod" in calls[0]
