#!/usr/bin/env python3
"""
Test workspace-first contract enforcement in dx-batch (bd-kuhj.3).

These tests verify that dx-batch properly validates workspace paths
and rejects canonical repo paths for mutating operations.
"""

import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import (
    ItemState,
    Phase,
    WaveOrchestrator,
    is_canonical_repo_path,
    resolve_item_worktree,
    validate_workspace_path,
)


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


class TestItemWorktreeResolution:
    """Test dx-batch resolution of the actual mutating worktree path."""

    def test_resolve_item_worktree_rejects_missing_workspace(self):
        worktree, reason, exit_code = resolve_item_worktree("bd-missing-worktree")

        assert worktree is None
        assert reason.startswith("worktree_missing:")
        assert exit_code == 1

    def test_resolve_item_worktree_rejects_multiple_worktrees(self, tmp_path):
        beads_id = "bd-ambiguous-worktree"
        workspace_root = Path("/tmp/agents") / beads_id
        repo_one = workspace_root / "agent-skills"
        repo_two = workspace_root / "llm-common"

        for repo in (repo_one, repo_two):
            repo.mkdir(parents=True, exist_ok=True)
            (repo / ".git").write_text("gitdir: /tmp/fake\n")

        with patch("dx_batch.is_git_worktree_path", return_value=True):
            worktree, reason, exit_code = resolve_item_worktree(beads_id)

        assert worktree is None
        assert reason.startswith("worktree_ambiguous:")
        assert str(repo_one) in reason
        assert str(repo_two) in reason
        assert exit_code == 1

    def test_resolve_item_worktree_accepts_single_workspace(self, tmp_path):
        beads_id = "bd-single-worktree"
        workspace = Path("/tmp/agents") / beads_id / "agent-skills"
        workspace.mkdir(parents=True, exist_ok=True)
        (workspace / ".git").write_text("gitdir: /tmp/fake\n")

        with patch("dx_batch.is_git_worktree_path", return_value=True):
            worktree, reason, exit_code = resolve_item_worktree(beads_id)

        assert worktree == workspace.resolve()
        assert reason == "workspace_resolved"
        assert exit_code == 0


class TestDispatchUsesExplicitWorktree:
    """Test that dx-batch passes an explicit worktree to dx-runner."""

    def test_dispatch_implement_passes_resolved_worktree(self, tmp_path, monkeypatch):
        monkeypatch.chdir(tmp_path)
        orchestrator = WaveOrchestrator("dispatch-implement-test")
        orchestrator.state = SimpleNamespace()
        item = ItemState(
            beads_id="bd-implement-worktree",
            attempt=1,
            provider="opencode",
            dx_runner_beads_id="bd-implement-worktree",
        )
        worktree = tmp_path / "workspace"
        worktree.mkdir()

        with patch("dx_batch.ARTIFACT_BASE", tmp_path / "artifacts"), patch(
            "dx_batch.resolve_item_worktree",
            return_value=(worktree, "workspace_resolved", 0),
        ), patch("dx_batch.subprocess.Popen") as mock_popen, patch.object(
            orchestrator.hygiene, "register_pid"
        ) as mock_register, patch.object(orchestrator, "save_state"), patch.object(
            orchestrator, "_release_lease"
        ), patch.object(orchestrator.artifacts, "write_error_outcome"):
            mock_popen.return_value.pid = 4242
            orchestrator._dispatch_implement(item)

        cmd = mock_popen.call_args.args[0]
        assert "--worktree" in cmd
        assert str(worktree) == cmd[cmd.index("--worktree") + 1]
        assert "--prompt-file" in cmd
        mock_register.assert_called_once_with(4242)

    def test_start_review_passes_resolved_worktree(self, tmp_path, monkeypatch):
        monkeypatch.chdir(tmp_path)
        orchestrator = WaveOrchestrator("dispatch-review-test")
        orchestrator.state = SimpleNamespace()
        item = ItemState(beads_id="bd-review-worktree", attempt=1)
        worktree = tmp_path / "workspace"
        worktree.mkdir()

        with patch("dx_batch.ARTIFACT_BASE", tmp_path / "artifacts"), patch(
            "dx_batch.resolve_item_worktree",
            return_value=(worktree, "workspace_resolved", 0),
        ), patch("dx_batch.subprocess.Popen") as mock_popen, patch.object(
            orchestrator.hygiene, "register_pid"
        ) as mock_register, patch.object(orchestrator, "save_state"), patch.object(
            orchestrator, "_release_lease"
        ), patch.object(orchestrator.artifacts, "write_error_outcome"):
            mock_popen.return_value.pid = 5252
            orchestrator._start_review(item)

        cmd = mock_popen.call_args.args[0]
        assert "--worktree" in cmd
        assert str(worktree) == cmd[cmd.index("--worktree") + 1]
        assert cmd[cmd.index("--beads") + 1] == "bd-review-worktree-review"
        mock_register.assert_called_once_with(5252)
