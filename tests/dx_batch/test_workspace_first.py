"""Tests for workspace-first gate in dx_batch (V8.6 parity with dx-runner)."""

import os
import shutil
import time
import uuid
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

import sys

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import (
    validate_worktree_path,
    check_workspace_first_gate,
    DEFAULT_ALLOWED_PREFIXES,
)


class TestValidateWorktreePath:
    """Test worktree path validation."""

    def test_valid_tmp_agents_path(self):
        """Standard /tmp/agents worktree path should be valid."""
        is_valid, reason = validate_worktree_path("/tmp/agents/bd-test/agent-skills")
        assert is_valid is True
        assert reason == "workspace_valid"

    def test_valid_tmp_dx_runner_path(self):
        """Standard /tmp/dx-runner path should be valid."""
        is_valid, reason = validate_worktree_path("/tmp/dx-runner/cc-glm/bd-test.log")
        assert is_valid is True
        assert reason == "workspace_valid"

    def test_valid_tmp_dxbench_path(self):
        """Standard /tmp/dxbench path should be valid."""
        is_valid, reason = validate_worktree_path("/tmp/dxbench/some-work")
        assert is_valid is True
        assert reason == "workspace_valid"

    def test_invalid_home_path(self):
        """Home directory paths should be invalid (canonical clone protection)."""
        is_valid, reason = validate_worktree_path("/home/user/agent-skills")
        assert is_valid is False
        assert "non_workspace_path" in reason

    def test_invalid_canonical_prime_radiant(self):
        """Canonical prime-radiant-ai path should be invalid."""
        is_valid, reason = validate_worktree_path(str(Path.home() / "prime-radiant-ai"))
        assert is_valid is False
        assert "non_workspace_path" in reason

    def test_invalid_actual_home_agent_skills(self):
        """Actual ~/agent-skills canonical should be invalid after fix."""
        is_valid, reason = validate_worktree_path(str(Path.home() / "agent-skills"))
        assert is_valid is False
        assert "non_workspace_path" in reason

    def test_empty_path_is_invalid(self):
        """Empty path should be invalid."""
        is_valid, reason = validate_worktree_path("")
        assert is_valid is False
        assert "empty" in reason.lower() or "worktree_path_empty" in reason

    def test_extra_allowed_prefixes_from_env(self, monkeypatch):
        """Extra prefixes from env should be respected."""
        monkeypatch.setenv("DX_RUNNER_EXTRA_ALLOWED_PREFIXES", "/custom/workspace")
        import importlib
        import dx_batch

        importlib.reload(dx_batch)

        is_valid, reason = dx_batch.validate_worktree_path("/custom/workspace/project")
        assert is_valid is True

    def test_symlink_resolution(self, tmp_path):
        """Symlinks should be resolved before checking."""
        link = tmp_path / "link_to_tmp"
        try:
            link.symlink_to("/tmp")
        except OSError:
            pytest.skip("Cannot create symlink")

        is_valid, reason = validate_worktree_path(str(link / "agents" / "test"))
        assert is_valid is True


class TestCheckWorkspaceFirstGate:
    """Test the workspace-first gate check."""

    def test_explicit_valid_worktree_passes(self):
        """Explicit valid worktree should pass gate."""
        passed, reason, worktree = check_workspace_first_gate(
            "bd-test", "/tmp/agents/bd-test/agent-skills"
        )
        assert passed is True
        assert "workspace_gate_passed" in reason

    def test_explicit_invalid_worktree_fails(self):
        """Explicit invalid worktree should fail gate."""
        passed, reason, worktree = check_workspace_first_gate(
            "bd-test", str(Path.home() / "agent-skills")
        )
        assert passed is False
        assert "gate_failed" in reason

    def test_deferred_to_runner_when_no_worktree(self):
        """Gate should defer to dx-runner when no worktree found."""
        passed, reason, worktree = check_workspace_first_gate("bd-nonexistent-xyz-test")
        assert passed is True
        assert "deferred_to_runner" in reason
        assert worktree == ""


class TestWorkspaceFirstGateIntegration:
    """Integration tests for workspace-first gate in dispatch flow."""

    def test_gate_blocks_canonical_dispatch(self, monkeypatch):
        """Gate should block dispatch to canonical repo via explicit worktree."""
        from dx_batch import WaveOrchestrator, WaveConfig, ItemState, ItemStatus

        wave = WaveOrchestrator("test-wave", WaveConfig())
        wave.state = MagicMock()
        wave.artifacts = MagicMock()

        item = ItemState(beads_id="bd-test")
        item.worktree = str(Path.home() / "agent-skills")

        wave._release_lease = MagicMock()
        wave.save_state = MagicMock()

        wave._dispatch_implement(item)

        assert item.status == ItemStatus.FAILED
        assert "workspace" in item.error.lower() or "gate" in item.error.lower(), (
            f"Unexpected error: {item.error}"
        )

    def test_gate_deferred_without_explicit_worktree(self, monkeypatch):
        """Gate should defer to dx-runner when no explicit worktree and no inferred one."""
        from dx_batch import WaveOrchestrator, WaveConfig, ItemState, ItemStatus

        wave = WaveOrchestrator("test-wave", WaveConfig())
        wave.state = MagicMock()
        wave.artifacts = MagicMock()
        wave.hygiene = MagicMock()

        item = ItemState(beads_id="bd-nonexistent-test-xyz")

        wave._release_lease = MagicMock()
        wave.save_state = MagicMock()

        with patch("subprocess.Popen") as mock_popen:
            mock_popen.return_value = MagicMock(pid=12345)
            wave._dispatch_implement(item)
            assert item.status != ItemStatus.FAILED

    def test_validate_worktree_path_rejects_canonical(self):
        """validate_worktree_path should reject canonical paths directly."""
        is_valid, reason = validate_worktree_path(str(Path.home() / "agent-skills"))
        assert is_valid is False
        assert "non_workspace_path" in reason

    def test_validate_worktree_path_accepts_workspace(self):
        """validate_worktree_path should accept /tmp/agents paths."""
        is_valid, reason = validate_worktree_path("/tmp/agents/bd-test/agent-skills")
        assert is_valid is True
        assert reason == "workspace_valid"


class TestCleanupProtection:
    """Tests for cleanup automation protection (V8.6 hardening).

    These tests use actual /tmp/agents paths with unique IDs to test
    the real worktree-cleanup.sh behavior deterministically.
    """

    @pytest.fixture
    def unique_beads_id(self):
        """Generate a unique beads_id for isolation."""
        return f"bd-test-{uuid.uuid4().hex[:8]}"

    @pytest.fixture
    def real_worktree_root(self, unique_beads_id):
        """Create a real worktree at /tmp/agents/<beads_id>/<repo>."""
        root = Path(f"/tmp/agents/{unique_beads_id}")
        repo_dir = root / "agent-skills"
        repo_dir.mkdir(parents=True, exist_ok=True)
        (repo_dir / ".git").write_text(
            f"gitdir: /home/user/agent-skills/.git/worktrees/{unique_beads_id}"
        )
        yield unique_beads_id, root
        if root.exists():
            shutil.rmtree(root, ignore_errors=True)

    def test_cleanup_works_on_valid_worktree(self, real_worktree_root):
        """worktree-cleanup.sh should clean up a valid worktree."""
        import subprocess

        beads_id, root = real_worktree_root
        assert root.exists(), f"Worktree root should exist: {root}"

        script_path = (
            Path(__file__).parent.parent.parent / "scripts" / "worktree-cleanup.sh"
        )
        result = subprocess.run(
            ["/bin/bash", str(script_path), beads_id],
            capture_output=True,
            text=True,
            timeout=30,
        )

        assert result.returncode == 0, (
            f"Cleanup failed: {result.stdout}\n{result.stderr}"
        )

    def test_cleanup_reports_not_found(self):
        """worktree-cleanup.sh should report not_found for nonexistent beads_id."""
        import subprocess

        script_path = (
            Path(__file__).parent.parent.parent / "scripts" / "worktree-cleanup.sh"
        )
        result = subprocess.run(
            ["/bin/bash", str(script_path), "bd-nonexistent-cleanup-test"],
            capture_output=True,
            text=True,
            timeout=30,
        )

        assert "not_found" in result.stdout or result.returncode == 0

    def test_session_lock_protection(self, unique_beads_id):
        """worktree-cleanup.sh should skip worktrees with fresh session locks."""
        import subprocess

        root = Path(f"/tmp/agents/{unique_beads_id}")
        repo_dir = root / "agent-skills"
        repo_dir.mkdir(parents=True, exist_ok=True)
        lock_file = repo_dir / ".dx-session-lock"

        lock_ts = int(time.time())
        lock_file.write_text(f"{lock_ts}:hostname:12345")

        try:
            script_path = (
                Path(__file__).parent.parent.parent / "scripts" / "worktree-cleanup.sh"
            )
            result = subprocess.run(
                ["/bin/bash", str(script_path), unique_beads_id],
                capture_output=True,
                text=True,
                timeout=30,
            )

            assert "SKIP" in result.stdout or "session_lock" in result.stdout.lower(), (
                f"Expected SKIP or session_lock, got: {result.stdout}"
            )

            assert root.exists(), "Worktree should NOT be deleted when locked"
        finally:
            if root.exists():
                shutil.rmtree(root, ignore_errors=True)

    def test_stale_session_lock_allows_cleanup(self, unique_beads_id):
        """worktree-cleanup.sh should allow cleanup of worktrees with stale locks (>4h)."""
        import subprocess

        root = Path(f"/tmp/agents/{unique_beads_id}")
        repo_dir = root / "agent-skills"
        repo_dir.mkdir(parents=True, exist_ok=True)
        lock_file = repo_dir / ".dx-session-lock"

        stale_ts = int(time.time()) - 15000
        lock_file.write_text(f"{stale_ts}:hostname:12345")

        script_path = (
            Path(__file__).parent.parent.parent / "scripts" / "worktree-cleanup.sh"
        )
        result = subprocess.run(
            ["/bin/bash", str(script_path), unique_beads_id],
            capture_output=True,
            text=True,
            timeout=30,
        )

        assert "SKIP" not in result.stdout, (
            f"Should not SKIP stale lock: {result.stdout}"
        )
