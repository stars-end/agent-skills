"""CLI smoke tests."""
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT_PATH = Path(__file__).parent.parent.parent / "scripts" / "dx-batch"


class TestCLISmoke:
    """CLI smoke tests."""

    def test_cli_help(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "--help"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "dx-batch" in result.stdout
        assert "start" in result.stdout
        assert "status" in result.stdout

    def test_cli_start_help(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "start", "--help"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "--items" in result.stdout
        assert "--wave-id" in result.stdout
        assert "--max-parallel" in result.stdout

    def test_cli_status_help(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "status", "--help"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "--wave-id" in result.stdout

    def test_cli_doctor_help(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "doctor", "--help"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "--wave-id" in result.stdout
        assert "--json" in result.stdout

    def test_cli_no_command_shows_help(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH)],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 1

    def test_cli_version(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "--version"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert "dx-batch" in result.stdout

    def test_cli_missing_wave_id_error(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "status"],
            capture_output=True,
            text=True,
        )
        assert result.returncode != 0

    def test_cli_start_missing_items_error(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "start"],
            capture_output=True,
            text=True,
        )
        assert result.returncode != 0
