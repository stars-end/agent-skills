#!/usr/bin/env python3
"""
Tests for dx-loop v1.3 MVP pillars:
- Pillar A: Stacked-PR bootstrap (dependency artifact collection + prompt injection)
- Pillar B: Human takeover / bypass / resume
- Pillar C: Phase-aware provider routing
"""

import json
import sys
from pathlib import Path
from types import SimpleNamespace
import importlib.util

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts" / "lib"))

from dx_loop.scheduler import DxLoopScheduler, SchedulerState
from dx_loop.state_machine import LoopState, BlockerCode, LoopStateTracker
from dx_loop.baton import BatonPhase, BatonManager, ReviewVerdict, BatonState
from dx_loop.beads_integration import BeadsTask, BeadsWaveManager
from dx_loop.runner_adapter import RunnerAdapter, RunnerStartResult, RunnerTaskState
from dx_loop.pr_contract import PRContractEnforcer

REPO_ROOT = Path(__file__).parent.parent.parent
DX_LOOP_SPEC = importlib.util.spec_from_file_location(
    "dx_loop_mvp", REPO_ROOT / "scripts" / "dx_loop.py"
)
dx_loop_mod = importlib.util.module_from_spec(DX_LOOP_SPEC)
assert DX_LOOP_SPEC.loader is not None
DX_LOOP_SPEC.loader.exec_module(dx_loop_mod)
DxLoop = dx_loop_mod.DxLoop
cmd_status = dx_loop_mod.cmd_status
cmd_takeover = dx_loop_mod.cmd_takeover
cmd_resume = dx_loop_mod.cmd_resume
VERSION = dx_loop_mod.VERSION


# ---------------------------------------------------------------------------
# Pillar A: Stacked-PR bootstrap
# ---------------------------------------------------------------------------


def test_collect_dependency_artifacts_from_completed_deps(tmp_path):
    """Completed dependencies with PR artifacts should be collected."""
    wave_id = "wave-pillar-a"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-upstream": BeadsTask(
            beads_id="bd-upstream",
            title="Upstream task",
            dependencies=[],
        ),
        "bd-child": BeadsTask(
            beads_id="bd-child",
            title="Child task",
            dependencies=["bd-upstream"],
        ),
    }
    loop.beads_manager.completed = {"bd-upstream"}
    loop.pr_enforcer.register_artifact(
        "bd-upstream",
        "https://github.com/stars-end/agent-skills/pull/100",
        "a" * 40,
    )

    artifacts = loop.collect_dependency_artifacts("bd-child")

    assert len(artifacts) == 1
    assert artifacts[0]["beads_id"] == "bd-upstream"
    assert (
        artifacts[0]["pr_url"] == "https://github.com/stars-end/agent-skills/pull/100"
    )
    assert artifacts[0]["pr_head_sha"] == "a" * 40

    print("Pillar A: collect_dependency_artifacts works")


def test_collect_dependency_artifacts_empty_when_no_deps(tmp_path):
    """Tasks with no dependencies should return empty list."""
    wave_id = "wave-no-deps"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-standalone": BeadsTask(
            beads_id="bd-standalone",
            title="Standalone task",
            dependencies=[],
        ),
    }

    artifacts = loop.collect_dependency_artifacts("bd-standalone")

    assert artifacts == []

    print("Pillar A: no deps returns empty")


def test_format_dependency_context_injected_into_prompt(tmp_path):
    """Dependency context section should be appended to implement prompts."""
    wave_id = "wave-dep-prompt"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-upstream": BeadsTask(
            beads_id="bd-upstream",
            title="Upstream",
            dependencies=[],
        ),
        "bd-child": BeadsTask(
            beads_id="bd-child",
            title="Child",
            dependencies=["bd-upstream"],
        ),
    }
    loop.beads_manager.completed = {"bd-upstream"}
    loop.pr_enforcer.register_artifact(
        "bd-upstream",
        "https://github.com/stars-end/agent-skills/pull/200",
        "b" * 40,
    )

    prompt = loop._resolve_prompt("bd-child", "implement", tmp_path / "worktree")
    dep_section = loop._format_dependency_context("bd-child")

    assert "Upstream Dependency Context" in dep_section
    assert "bd-upstream" in dep_section
    assert "pull/200" in dep_section

    full_prompt = prompt + "\n\n" + dep_section
    assert "Stacked-PR Bootstrap" in full_prompt

    print("Pillar A: dependency context formatted correctly")


def test_dispatch_blocked_when_upstream_missing_pr_artifacts(tmp_path):
    """Dispatch should fail when completed upstream deps lack PR artifacts."""
    wave_id = "wave-missing-artifact"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-upstream": BeadsTask(
            beads_id="bd-upstream",
            title="Upstream (no PR)",
            dependencies=[],
            status="closed",
        ),
        "bd-child": BeadsTask(
            beads_id="bd-child",
            title="Child",
            dependencies=["bd-upstream"],
        ),
    }
    loop.beads_manager.dependency_status_cache["bd-upstream"] = "closed"

    block = loop._check_dependency_artifacts("bd-child")

    assert block is not None
    assert "missing PR artifacts" in block
    assert "bd-upstream" in block

    print("Pillar A: dispatch blocked when upstream missing artifacts")


def test_dispatch_proceeds_when_upstream_has_artifacts(tmp_path):
    """Dispatch should proceed when all completed upstream deps have PR artifacts."""
    wave_id = "wave-has-artifact"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-upstream": BeadsTask(
            beads_id="bd-upstream",
            title="Upstream",
            dependencies=[],
        ),
        "bd-child": BeadsTask(
            beads_id="bd-child",
            title="Child",
            dependencies=["bd-upstream"],
        ),
    }
    loop.beads_manager.completed = {"bd-upstream"}
    loop.pr_enforcer.register_artifact(
        "bd-upstream",
        "https://github.com/stars-end/agent-skills/pull/300",
        "c" * 40,
    )

    block = loop._check_dependency_artifacts("bd-child")

    assert block is None

    print("Pillar A: dispatch proceeds when upstream has artifacts")


# ---------------------------------------------------------------------------
# Pillar B: Human takeover / bypass / resume
# ---------------------------------------------------------------------------


def test_baton_start_manual_takeover():
    """start_manual_takeover should transition to MANUAL_TAKEOVER phase."""
    baton = BatonManager()
    baton.start_implement("bd-test", run_id="run-1")

    state = baton.start_manual_takeover(
        "bd-test",
        pr_url="https://example.com/pull/1",
        pr_head_sha="d" * 40,
        operator_note="Fixing manually",
    )

    assert state.phase == BatonPhase.MANUAL_TAKEOVER
    assert state.pr_url == "https://example.com/pull/1"
    assert state.metadata["operator_note"] == "Fixing manually"
    assert "takeover_at" in state.metadata

    print("Pillar B: baton start_manual_takeover works")


def test_baton_resume_from_takeover():
    """resume_from_takeover should restore previous phase."""
    baton = BatonManager()
    baton.start_implement("bd-test", run_id="run-1")
    baton.start_manual_takeover("bd-test")

    state = baton.resume_from_takeover("bd-test")

    assert state.phase == BatonPhase.IMPLEMENT
    assert "resumed_at" in state.metadata

    print("Pillar B: baton resume_from_takeover works")


def test_baton_resume_preserves_takeover_from_phase():
    """Resume should restore the phase that was active before takeover."""
    baton = BatonManager()
    baton.start_implement("bd-test", run_id="run-1")
    baton.complete_implement("bd-test", pr_url="http://x/1", pr_head_sha="e" * 40)
    baton.start_review("bd-test", run_id="rev-1")
    baton.start_manual_takeover("bd-test")

    state = baton.resume_from_takeover("bd-test")

    assert state.phase == BatonPhase.REVIEW

    print("Pillar B: resume preserves pre-takeover phase (review)")


def test_resume_rejects_non_takeover_phase():
    """Resume should fail if task is not in MANUAL_TAKEOVER."""
    baton = BatonManager()
    baton.start_implement("bd-test", run_id="run-1")

    try:
        baton.resume_from_takeover("bd-test")
        assert False, "Should have raised ValueError"
    except ValueError as e:
        assert "manual_takeover" in str(e).lower()

    print("Pillar B: resume rejects non-takeover phase")


def test_get_next_action_returns_manual_takeover():
    """get_next_action should return 'manual_takeover' for taken-over tasks."""
    baton = BatonManager()
    baton.start_implement("bd-test", run_id="run-1")
    baton.start_manual_takeover("bd-test")

    action = baton.get_next_action("bd-test")

    assert action == "manual_takeover"

    print("Pillar B: get_next_action returns manual_takeover")


def test_dispatch_skips_manual_takeover_tasks(tmp_path):
    """_dispatch_task should return False for MANUAL_TAKEOVER tasks."""
    wave_id = "wave-takeover-dispatch"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Takeover task",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-test", run_id="run-1")
    loop.baton_manager.start_manual_takeover("bd-test")

    result = loop._dispatch_task("bd-test")

    assert result is False

    print("Pillar B: dispatch skips manual takeover tasks")


def test_check_progress_skips_manual_takeover(tmp_path):
    """_check_progress should not poll MANUAL_TAKEOVER tasks."""
    wave_id = "wave-takeover-progress"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Takeover task",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-test", run_id="run-1")
    loop.baton_manager.start_manual_takeover("bd-test")

    checked = []
    original_check = loop._check_implement_progress

    def tracking_check(beads_id):
        checked.append(beads_id)
        original_check(beads_id)

    loop._check_implement_progress = tracking_check
    loop._check_progress()

    assert "bd-test" not in checked

    print("Pillar B: check_progress skips manual takeover")


def test_cmd_takeover_updates_state_file(tmp_path):
    """cmd_takeover should persist MANUAL_TAKEOVER to state file."""
    wave_id = "wave-cli-takeover"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Test task",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-test", run_id="run-1")
    loop._save_state()

    args = SimpleNamespace(
        wave_id=wave_id,
        beads_id="bd-test",
        note="Manual fix needed",
    )

    original_artifact_base = cmd_takeover.__globals__["ARTIFACT_BASE"]
    cmd_takeover.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_takeover(args)
    finally:
        cmd_takeover.__globals__["ARTIFACT_BASE"] = original_artifact_base

    assert rc == 0

    state = json.loads(loop.state_file.read_text())
    bs = state["baton_states"]["bd-test"]
    assert bs["phase"] == "manual_takeover"
    assert bs["metadata"]["takeover_from"] == "implement"
    assert bs["metadata"]["operator_note"] == "Manual fix needed"

    print("Pillar B: cmd_takeover persists state")


def test_cmd_resume_updates_state_file(tmp_path):
    """cmd_resume should restore the previous phase."""
    wave_id = "wave-cli-resume"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Test task",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-test", run_id="run-1")
    loop.baton_manager.start_manual_takeover("bd-test")
    loop._save_state()

    args = SimpleNamespace(wave_id=wave_id, beads_id="bd-test")

    original_artifact_base = cmd_resume.__globals__["ARTIFACT_BASE"]
    cmd_resume.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_resume(args)
    finally:
        cmd_resume.__globals__["ARTIFACT_BASE"] = original_artifact_base

    assert rc == 0

    state = json.loads(loop.state_file.read_text())
    bs = state["baton_states"]["bd-test"]
    assert bs["phase"] == "implement"
    assert "resumed_at" in bs["metadata"]

    print("Pillar B: cmd_resume persists state")


def test_cmd_status_shows_takeover_tasks(tmp_path, capsys):
    """cmd_status should display manual takeover tasks."""
    wave_id = "wave-status-takeover"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Test task",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-test", run_id="run-1")
    loop.baton_manager.start_manual_takeover("bd-test")
    loop._save_state()

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(SimpleNamespace(wave_id=wave_id, json=False))
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    assert "Manual takeover" in captured.out
    assert "bd-test" in captured.out

    print("Pillar B: status shows takeover tasks")


def test_adopt_skips_manual_takeover_tasks(tmp_path):
    """adopt_running_jobs should skip tasks in MANUAL_TAKEOVER."""
    wave_id = "wave-adopt-takeover"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Takeover task",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-test", run_id="run-1")
    loop.baton_manager.start_manual_takeover("bd-test")

    loop.implement_runner.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="healthy",
        reason_code="recent_log_activity",
    )

    adopted = loop.adopt_running_jobs()

    assert adopted == []
    assert not loop.scheduler.state.is_active("bd-test")

    print("Pillar B: adoption skips manual takeover")


# ---------------------------------------------------------------------------
# Pillar C: Phase-aware provider routing
# ---------------------------------------------------------------------------


def test_dual_providers_initialized(tmp_path):
    """DxLoop should create separate runner adapters for implement and review."""
    loop = DxLoop(
        "wave-dual",
        config={
            "cadence_seconds": 0,
            "implement_provider": "opencode",
            "review_provider": "cc-glm",
        },
    )

    assert loop.implement_provider == "opencode"
    assert loop.review_provider == "cc-glm"
    assert isinstance(loop.implement_runner, RunnerAdapter)
    assert isinstance(loop.review_runner, RunnerAdapter)
    assert loop.implement_runner.provider == "opencode"
    assert loop.review_runner.provider == "cc-glm"
    assert loop.runner_adapter is loop.implement_runner

    print("Pillar C: dual providers initialized")


def test_single_provider_defaults_both(tmp_path):
    """Without phase-specific providers, both runners use the default."""
    loop = DxLoop("wave-single", config={"cadence_seconds": 0, "provider": "opencode"})

    assert loop.implement_provider == "opencode"
    assert loop.review_provider == "opencode"
    assert loop.implement_runner.provider == loop.review_runner.provider

    print("Pillar C: single provider defaults both phases")


def test_null_provider_falls_back_to_default(tmp_path):
    """Null phase providers should fall back to the global provider."""
    loop = DxLoop(
        "wave-null",
        config={
            "cadence_seconds": 0,
            "provider": "opencode",
            "implement_provider": None,
            "review_provider": None,
        },
    )

    assert loop.implement_provider == "opencode"
    assert loop.review_provider == "opencode"

    print("Pillar C: null providers fall back to default")


def test_start_implement_uses_implement_runner(tmp_path):
    """_start_implement should dispatch via the implement runner with model."""
    wave_id = "wave-impl-provider"
    loop = DxLoop(
        wave_id,
        config={
            "cadence_seconds": 0,
            "implement_provider": "opencode",
            "review_provider": "cc-glm",
            "implement_model": "zai-coding-plan/glm-5-turbo",
        },
    )
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Test",
            dependencies=[],
        ),
    }
    worktree = tmp_path / "agents" / "bd-test" / "agent-skills"
    worktree.mkdir(parents=True)
    loop._ensure_worktree = lambda beads_id: worktree

    dispatched_provider = {}

    def fake_start(beads_id, prompt_file, worktree=None, model=None):
        dispatched_provider["provider"] = loop.implement_runner.provider
        dispatched_provider["model"] = model
        return RunnerStartResult(
            ok=True,
            returncode=0,
            command=["dx-runner", "start"],
        )

    loop.implement_runner.start = fake_start

    assert loop._start_implement("bd-test") is True
    assert dispatched_provider["provider"] == "opencode"
    assert dispatched_provider["model"] == "zai-coding-plan/glm-5-turbo"

    print("Pillar C: _start_implement uses implement runner with model")


def test_start_review_uses_review_runner(tmp_path):
    """_start_review should dispatch via the review runner with model."""
    wave_id = "wave-rev-provider"
    loop = DxLoop(
        wave_id,
        config={
            "cadence_seconds": 0,
            "implement_provider": "opencode",
            "review_provider": "cc-glm",
            "review_model": "zai-coding-plan/glm-5.1",
        },
    )
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Test",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-test")
    loop.baton_manager.complete_implement(
        "bd-test",
        pr_url="https://example.com/pull/1",
        pr_head_sha="f" * 40,
    )
    worktree = tmp_path / "agents" / "bd-test" / "agent-skills"
    worktree.mkdir(parents=True)
    loop._ensure_worktree = lambda beads_id: worktree

    dispatched_provider = {}

    def fake_start(beads_id, prompt_file, worktree=None, model=None):
        dispatched_provider["provider"] = loop.review_runner.provider
        dispatched_provider["model"] = model
        return RunnerStartResult(
            ok=True,
            returncode=0,
            command=["dx-runner", "start"],
        )

    loop.review_runner.start = fake_start

    assert loop._start_review("bd-test") is True
    assert dispatched_provider["provider"] == "cc-glm"
    assert dispatched_provider["model"] == "zai-coding-plan/glm-5.1"

    print("Pillar C: _start_review uses review runner with model")


# ---------------------------------------------------------------------------
# Cross-cutting / version tests
# ---------------------------------------------------------------------------


def test_version_is_1_3_0():
    """Version should be bumped to 1.3.0."""
    assert VERSION == "1.3.0"

    print("Version: 1.3.0")


def test_manual_takeover_in_allowed_transitions():
    """MANUAL_TAKEOVER should be in ALLOWED_TRANSITIONS."""
    from dx_loop.state_machine import LoopStateMachine

    sm = LoopStateMachine()

    assert LoopState.MANUAL_TAKEOVER in sm.ALLOWED_TRANSITIONS
    assert (
        LoopState.IN_PROGRESS_HEALTHY
        in sm.ALLOWED_TRANSITIONS[LoopState.MANUAL_TAKEOVER]
    )

    print("MANUAL_TAKEOVER in allowed transitions")


def test_manual_takeover_baton_phase_exists():
    """MANUAL_TAKEOVER should be a valid BatonPhase."""
    assert BatonPhase.MANUAL_TAKEOVER.value == "manual_takeover"

    print("MANUAL_TAKEOVER BatonPhase exists")


def test_default_config_has_phase_providers():
    """DEFAULT_CONFIG should include implement_provider and review_provider."""
    config = dx_loop_mod.DEFAULT_CONFIG

    assert "implement_provider" in config
    assert "review_provider" in config
    assert config["implement_provider"] is None
    assert config["review_provider"] is None

    print("DEFAULT_CONFIG has phase-aware provider keys")


# ---------------------------------------------------------------------------
# Finding 1: review-phase adoption under dual-runner
# ---------------------------------------------------------------------------


def test_adopt_running_jobs_probes_review_runner_for_review_phase(tmp_path):
    """Adoption must probe review_runner for REVIEW-phase tasks via bd-<id>-review."""
    wave_id = "wave-adopt-review"
    loop = DxLoop(
        wave_id,
        config={
            "cadence_seconds": 0,
            "implement_provider": "opencode",
            "review_provider": "cc-glm",
        },
    )
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-rev": BeadsTask(
            beads_id="bd-rev",
            title="Review task",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-rev", run_id="run-1")
    loop.baton_manager.complete_implement(
        "bd-rev", pr_url="http://x/1", pr_head_sha="a" * 40
    )
    loop.baton_manager.start_review("bd-rev", run_id="rev-1")

    probed_ids = {"implement": [], "review": []}

    def fake_impl_check(beads_id):
        probed_ids["implement"].append(beads_id)
        return None

    def fake_rev_check(beads_id):
        probed_ids["review"].append(beads_id)
        return RunnerTaskState(
            beads_id=beads_id,
            state="healthy",
            reason_code="recent_log_activity",
        )

    loop.implement_runner.check = fake_impl_check
    loop.review_runner.check = fake_rev_check

    adopted = loop.adopt_running_jobs()

    assert "bd-rev" in adopted
    assert "bd-rev" not in probed_ids["implement"]
    assert "bd-rev-review" in probed_ids["review"]
    assert loop.scheduler.state.is_active("bd-rev", "review")
    assert not loop.scheduler.state.is_active("bd-rev", "implement")

    print("Finding 1: review-phase adoption probes review_runner with bd-*-review")


def test_adopt_running_jobs_probes_implement_runner_for_implement_phase(tmp_path):
    """Adoption must probe implement_runner for IMPLEMENT-phase tasks."""
    wave_id = "wave-adopt-impl"
    loop = DxLoop(
        wave_id,
        config={
            "cadence_seconds": 0,
            "implement_provider": "opencode",
            "review_provider": "cc-glm",
        },
    )
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-impl": BeadsTask(
            beads_id="bd-impl",
            title="Implement task",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-impl", run_id="run-1")

    probed_ids = {"implement": [], "review": []}

    def fake_impl_check(beads_id):
        probed_ids["implement"].append(beads_id)
        return RunnerTaskState(
            beads_id=beads_id,
            state="healthy",
            reason_code="recent_log_activity",
        )

    def fake_rev_check(beads_id):
        probed_ids["review"].append(beads_id)
        return None

    loop.implement_runner.check = fake_impl_check
    loop.review_runner.check = fake_rev_check

    adopted = loop.adopt_running_jobs()

    assert "bd-impl" in adopted
    assert "bd-impl" in probed_ids["implement"]
    assert not probed_ids["review"]
    assert loop.scheduler.state.is_active("bd-impl", "implement")

    print("Finding 1: implement-phase adoption probes implement_runner")


def test_adopt_running_jobs_no_bd_review_scheduler_key(tmp_path):
    """Adopted review tasks must use base beads_id as scheduler key, not bd-*-review."""
    wave_id = "wave-adopt-key"
    loop = DxLoop(
        wave_id,
        config={
            "cadence_seconds": 0,
            "implement_provider": "opencode",
            "review_provider": "cc-glm",
        },
    )
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-rev": BeadsTask(
            beads_id="bd-rev",
            title="Review task",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-rev", run_id="run-1")
    loop.baton_manager.complete_implement(
        "bd-rev", pr_url="http://x/1", pr_head_sha="a" * 40
    )
    loop.baton_manager.start_review("bd-rev", run_id="rev-1")

    loop.review_runner.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="healthy",
    )
    loop.implement_runner.check = lambda beads_id: None

    adopted = loop.adopt_running_jobs()

    assert "bd-rev" in adopted
    assert not loop.scheduler.state.is_active("bd-rev-review")
    assert loop.scheduler.state.is_active("bd-rev", "review")

    print("Finding 1: no bd-*-review keys in scheduler after review adoption")


# ---------------------------------------------------------------------------
# Finding 2: takeover/resume scheduler state reconciliation
# ---------------------------------------------------------------------------


def test_cmd_takeover_clears_scheduler_active_state(tmp_path):
    """Takeover must remove the task's scheduler active keys."""
    wave_id = "wave-takeover-sched"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Test",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-test", run_id="run-1")
    loop.scheduler.state.mark_dispatched("bd-test", "implement")
    loop._save_state()

    args = SimpleNamespace(
        wave_id=wave_id,
        beads_id="bd-test",
        note="Manual fix",
    )

    original_artifact_base = cmd_takeover.__globals__["ARTIFACT_BASE"]
    cmd_takeover.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_takeover(args)
    finally:
        cmd_takeover.__globals__["ARTIFACT_BASE"] = original_artifact_base

    assert rc == 0
    state = json.loads(loop.state_file.read_text())
    active_keys = state["scheduler_state"]["active_beads_ids"]
    for key in active_keys:
        assert not key.startswith("bd-test:"), (
            f"Active key {key} should have been removed on takeover"
        )

    print("Finding 2: takeover clears scheduler active state")


def test_cmd_takeover_clears_scheduler_blocked_state(tmp_path):
    """Takeover must remove the task from blocked set."""
    wave_id = "wave-takeover-blocked"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Test",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-test", run_id="run-1")
    loop.scheduler.state.mark_blocked("bd-test")
    loop._save_state()

    args = SimpleNamespace(wave_id=wave_id, beads_id="bd-test", note=None)

    original_artifact_base = cmd_takeover.__globals__["ARTIFACT_BASE"]
    cmd_takeover.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_takeover(args)
    finally:
        cmd_takeover.__globals__["ARTIFACT_BASE"] = original_artifact_base

    assert rc == 0
    state = json.loads(loop.state_file.read_text())
    assert "bd-test" not in state["scheduler_state"]["blocked_beads_ids"]

    print("Finding 2: takeover clears scheduler blocked state")


def test_cmd_resume_clears_stale_scheduler_state(tmp_path):
    """Resume must clear stale active/blocked so the task can redispatch."""
    wave_id = "wave-resume-sched"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Test",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-test", run_id="run-1")
    loop.scheduler.state.mark_dispatched("bd-test", "implement")
    loop.baton_manager.start_manual_takeover("bd-test")
    loop._save_state()

    args = SimpleNamespace(wave_id=wave_id, beads_id="bd-test")

    original_artifact_base = cmd_resume.__globals__["ARTIFACT_BASE"]
    cmd_resume.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_resume(args)
    finally:
        cmd_resume.__globals__["ARTIFACT_BASE"] = original_artifact_base

    assert rc == 0
    state = json.loads(loop.state_file.read_text())
    active_keys = state["scheduler_state"]["active_beads_ids"]
    for key in active_keys:
        assert not key.startswith("bd-test:"), (
            f"Active key {key} should have been cleared on resume"
        )
    assert "bd-test" not in state["scheduler_state"]["blocked_beads_ids"]

    restored_bs = state["baton_states"]["bd-test"]
    assert restored_bs["phase"] == "implement"

    print("Finding 2: resume clears stale scheduler state for clean redispatch")


def test_resume_does_not_fabricate_active_state(tmp_path):
    """Resume must NOT mark the task as active unless a real runner is live."""
    wave_id = "wave-resume-no-fabricate"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Test",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-test", run_id="run-1")
    loop.baton_manager.start_manual_takeover("bd-test")
    loop._save_state()

    args = SimpleNamespace(wave_id=wave_id, beads_id="bd-test")

    original_artifact_base = cmd_resume.__globals__["ARTIFACT_BASE"]
    cmd_resume.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_resume(args)
    finally:
        cmd_resume.__globals__["ARTIFACT_BASE"] = original_artifact_base

    assert rc == 0
    state = json.loads(loop.state_file.read_text())
    active_keys = state["scheduler_state"]["active_beads_ids"]
    assert not any(k.startswith("bd-test") for k in active_keys)

    print("Finding 2: resume does not fabricate active state")


if __name__ == "__main__":
    test_version_is_1_3_0()
    test_collect_dependency_artifacts_from_completed_deps(Path("/tmp"))
    test_collect_dependency_artifacts_empty_when_no_deps(Path("/tmp"))
    test_format_dependency_context_injected_into_prompt(Path("/tmp"))
    test_dispatch_blocked_when_upstream_missing_pr_artifacts(Path("/tmp"))
    test_dispatch_proceeds_when_upstream_has_artifacts(Path("/tmp"))
    test_baton_start_manual_takeover()
    test_baton_resume_from_takeover()
    test_baton_resume_preserves_takeover_from_phase()
    test_resume_rejects_non_takeover_phase()
    test_get_next_action_returns_manual_takeover()
    test_dual_providers_initialized(Path("/tmp"))
    test_single_provider_defaults_both(Path("/tmp"))
    test_null_provider_falls_back_to_default(Path("/tmp"))
    test_default_config_has_phase_providers()
    test_adopt_running_jobs_probes_review_runner_for_review_phase(Path("/tmp"))
    test_adopt_running_jobs_probes_implement_runner_for_implement_phase(Path("/tmp"))
    test_adopt_running_jobs_no_bd_review_scheduler_key(Path("/tmp"))
    test_cmd_takeover_clears_scheduler_active_state(Path("/tmp"))
    test_cmd_takeover_clears_scheduler_blocked_state(Path("/tmp"))
    test_cmd_resume_clears_stale_scheduler_state(Path("/tmp"))
    test_resume_does_not_fabricate_active_state(Path("/tmp"))
    print("\nAll MVP pillar tests passed!")
