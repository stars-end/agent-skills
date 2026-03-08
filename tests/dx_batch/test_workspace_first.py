#!/usr/bin/env python3
"""
Test workspace-first contract enforcement in dx-batch (bd-kuhj.3).

These tests verify that dx-batch properly validates workspace paths
and rejects canonical repo paths for mutating operations.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import is_canonical_repo_path, validate_workspace_path


class TestCanonicalRepoDetection:
    """Test is_canonical_repo_path function."""

    def test_detects_agent_skills(self):
        """Should detect ~/agent-skills as canonical."""
        canonical = Path.home() / "agent-skills"
        assert is_canonical_repo_path(canonical)

    def test_detects_agent_skills_descendant(self):
        """Should detect ~/agent-skills/subdir as canonical descendant."""
        descendant = Path.home() / "agent-skills" / "scripts" / "dx_batch.py"
        assert is_canonical_repo_path(descendant)

    def test_detects_prime_radiant_ai(self):
        """Should detect ~/prime-radiant-ai as canonical."""
        canonical = Path.home() / "prime-radiant-ai"
        assert is_canonical_repo_path(canonical)

    def test_detects_affordabot(self):
        """Should detect ~/affordabot as canonical."""
        canonical = Path.home() / "affordabot"
        assert is_canonical_repo_path(canonical)

    def test_detects_llm_common(self):
        """Should detect ~/llm-common as canonical."""
        canonical = Path.home() / "llm-common"
        assert is_canonical_repo_path(canonical)

    def test_allows_tmp_agents(self):
        """Should allow /tmp/agents paths."""
        workspace = Path("/tmp/agents/bd-test/agent-skills")
        assert not is_canonical_repo_path(workspace)

    def test_allows_tmp_dx_runner(self):
        """Should allow /tmp/dx-runner paths."""
        workspace = Path("/tmp/dx-runner/opencode/bd-test.log")
        assert not is_canonical_repo_path(workspace)

    def test_allows_arbitrary_path(self):
        """Should allow arbitrary non-canonical paths."""
        workspace = Path("/var/tmp/some-project")
        assert not is_canonical_repo_path(workspace)

    def test_handles_nonexistent_path(self):
        """Should handle nonexistent paths gracefully."""
        nonexistent = Path("/nonexistent/path/to/nowhere")
        assert not is_canonical_repo_path(nonexistent)


class TestWorkspacePathValidation:
    """Test validate_workspace_path function."""

    def test_rejects_canonical_agent_skills(self):
        """Should reject ~/agent-skills with exit code 22."""
        canonical = Path.home() / "agent-skills"
        is_valid, reason, exit_code = validate_workspace_path(canonical)

        assert not is_valid
        assert "canonical_worktree_forbidden" in reason
        assert exit_code == 22

    def test_rejects_canonical_descendant(self):
        """Should reject ~/agent-skills/subdir with exit code 22."""
        descendant = Path.home() / "agent-skills" / "scripts"
        is_valid, reason, exit_code = validate_workspace_path(descendant)

        assert not is_valid
        assert "canonical_worktree_forbidden" in reason
        assert exit_code == 22

    def test_accepts_tmp_agents(self):
        """Should accept /tmp/agents paths."""
        workspace = Path("/tmp/agents/bd-test/agent-skills")
        is_valid, reason, exit_code = validate_workspace_path(workspace)

        assert is_valid
        assert "workspace_allowed" in reason
        assert exit_code == 0

    def test_accepts_tmp_dx_runner(self):
        """Should accept /tmp/dx-runner paths."""
        workspace = Path("/tmp/dx-runner/opencode/bd-test")
        is_valid, reason, exit_code = validate_workspace_path(workspace)

        assert is_valid
        assert "workspace_allowed" in reason
        assert exit_code == 0

    def test_accepts_tmp_dxbench(self):
        """Should accept /tmp/dxbench paths."""
        workspace = Path("/tmp/dxbench/suite-1")
        is_valid, reason, exit_code = validate_workspace_path(workspace)

        assert is_valid
        assert "workspace_allowed" in reason
        assert exit_code == 0

    def test_accepts_none_path(self):
        """Should accept None path (no workspace path provided)."""
        is_valid, reason, exit_code = validate_workspace_path(None)

        assert is_valid
        assert reason == "no_workspace_path"
        assert exit_code == 0

    def test_rejects_arbitrary_path(self):
        """Should reject arbitrary paths not in allowed prefixes."""
        arbitrary = Path("/var/tmp/unknown-location")
        is_valid, reason, exit_code = validate_workspace_path(arbitrary)

        assert not is_valid
        assert "non_workspace_path" in reason
        assert exit_code == 1

    def test_accepts_extra_prefix_from_env(self, monkeypatch):
        """Should accept paths from DX_RUNNER_EXTRA_ALLOWED_PREFIXES."""
        monkeypatch.setenv(
            "DX_RUNNER_EXTRA_ALLOWED_PREFIXES", "/custom/workspace,/another/path"
        )

        # Reimport to pick up env change
        import importlib

        import dx_batch

        importlib.reload(dx_batch)

        workspace = Path("/custom/workspace/bd-test")
        is_valid, reason, exit_code = dx_batch.validate_workspace_path(workspace)

        assert is_valid
        assert "workspace_allowed" in reason
        assert exit_code == 0

    def test_allows_tmp_dxbench_epyc6(self):
        """Should accept /tmp/dxbench_epyc6 paths."""
        workspace = Path("/tmp/dxbench_epyc6/benchmark-1")
        is_valid, reason, exit_code = validate_workspace_path(workspace)

        assert is_valid
        assert "workspace_allowed" in reason
        assert exit_code == 0


class TestWorkspaceValidationExitCodes:
    """Test that exit codes match dx-runner contract."""

    def test_canonical_rejection_returns_22(self):
        """Canonical rejection should return exit code 22."""
        canonical = Path.home() / "agent-skills"
        _, _, exit_code = validate_workspace_path(canonical)

        assert exit_code == 22

    def test_allowed_workspace_returns_0(self):
        """Allowed workspace should return exit code 0."""
        workspace = Path("/tmp/agents/bd-test")
        _, _, exit_code = validate_workspace_path(workspace)

        assert exit_code == 0

    def test_non_workspace_returns_1(self):
        """Non-workspace path should return exit code 1."""
        non_workspace = Path("/usr/local/bin")
        _, _, exit_code = validate_workspace_path(non_workspace)

        assert exit_code == 1
