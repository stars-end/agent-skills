#!/usr/bin/env python3
"""
Tests for dx-loop v1.1 fixes:
- P0: No duplicate dispatch
- P1: Notification logic
- P1: State persistence
- Operator surface fixes
"""

import json
import os
import sys
import subprocess
import threading
from pathlib import Path
from types import SimpleNamespace
import importlib.util

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts" / "lib"))

from dx_loop.scheduler import DxLoopScheduler, SchedulerState
from dx_loop.state_machine import LoopState, BlockerCode, LoopStateTracker
from dx_loop.baton import BatonPhase, BatonManager, ReviewVerdict, BatonState
from dx_loop.beads_integration import BeadsTask, BeadsWaveManager
from dx_loop.blocker import BlockerClassifier
from dx_loop.notifications import NotificationManager
from dx_loop.runner_adapter import RunnerAdapter, RunnerStartResult, RunnerTaskState
from dx_loop.pr_contract import PRContractEnforcer

REPO_ROOT = Path(__file__).parent.parent.parent
DX_LOOP_SPEC = importlib.util.spec_from_file_location(
    "dx_loop_script", REPO_ROOT / "scripts" / "dx_loop.py"
)
dx_loop_script = importlib.util.module_from_spec(DX_LOOP_SPEC)
assert DX_LOOP_SPEC.loader is not None
DX_LOOP_SPEC.loader.exec_module(dx_loop_script)
DxLoop = dx_loop_script.DxLoop
cmd_status = dx_loop_script.cmd_status
cmd_explain = dx_loop_script.cmd_explain
cmd_start = dx_loop_script.cmd_start


def _build_stale_closed_review_wave(tmp_path: Path, wave_id: str = "wave-stale-closed"):
    """Create a persisted wave pinned on an active review task that is now closed."""
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.epic_id = "bd-bkco"
    loop.beads_manager.tasks = {
        "bd-bkco.2": BeadsTask(
            beads_id="bd-bkco.2",
            title="Merged task",
            repo="agent-skills",
            dependencies=[],
            status="open",
            details_loaded=True,
        ),
        "bd-bkco.3": BeadsTask(
            beads_id="bd-bkco.3",
            title="Downstream task",
            repo="agent-skills",
            dependencies=["bd-bkco.2"],
            status="open",
            details_loaded=True,
        ),
    }
    loop.beads_manager.layers = [["bd-bkco.2"], ["bd-bkco.3"]]
    loop.baton_manager.start_implement("bd-bkco.2")
    loop.baton_manager.complete_implement(
        "bd-bkco.2", pr_url="https://example/pr/344", pr_head_sha="a" * 40
    )
    loop.baton_manager.start_review("bd-bkco.2", run_id="review-run-1")
    loop.scheduler.state.mark_dispatched("bd-bkco.2", "review")
    loop._set_wave_status(
        LoopState.IN_PROGRESS_HEALTHY,
        None,
        "All ready tasks already active, waiting for progress",
        dispatchable_tasks=["bd-bkco.2"],
    )
    loop._save_state()
    return loop


def _build_stale_closed_epic_frontier_wave(
    tmp_path: Path, wave_id: str = "wave-stale-epic-frontier"
):
    """Create a persisted wave with stale cached open children under a closed epic."""
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.epic_id = "bd-bkco"
    loop.beads_manager.tasks = {
        "bd-bkco.2": BeadsTask(
            beads_id="bd-bkco.2",
            title="Merged prerequisite",
            repo="affordabot",
            dependencies=[],
            status="closed",
            details_loaded=True,
        ),
        "bd-bkco.3": BeadsTask(
            beads_id="bd-bkco.3",
            title="Stale child A",
            repo="affordabot",
            dependencies=["bd-bkco.2"],
            status="open",
            details_loaded=True,
        ),
        "bd-bkco.4": BeadsTask(
            beads_id="bd-bkco.4",
            title="Stale child B",
            repo="affordabot",
            dependencies=["bd-bkco.2"],
            status="open",
            details_loaded=True,
        ),
        "bd-bkco.5": BeadsTask(
            beads_id="bd-bkco.5",
            title="Stale child C",
            repo="affordabot",
            dependencies=["bd-bkco.2"],
            status="open",
            details_loaded=True,
        ),
        "bd-bkco.6": BeadsTask(
            beads_id="bd-bkco.6",
            title="Stale child D",
            repo="affordabot",
            dependencies=["bd-bkco.2", "bd-bkco.3", "bd-bkco.4", "bd-bkco.5"],
            status="open",
            details_loaded=True,
        ),
    }
    loop.beads_manager.completed = {"bd-bkco.1", "bd-bkco.2"}
    loop.beads_manager.layers = [["bd-bkco.2", "bd-bkco.3", "bd-bkco.4", "bd-bkco.5"]]
    loop.scheduler.state.active_beads_ids = set()
    loop.scheduler.state.blocked_beads_ids = set()
    loop._set_wave_status(
        LoopState.IN_PROGRESS_HEALTHY,
        None,
        "Reconciled wave state; 3 task(s) ready for dispatch",
        dispatchable_tasks=["bd-bkco.3", "bd-bkco.4", "bd-bkco.5"],
    )
    loop._save_state()
    return loop


def _build_stale_waiting_closed_epic_frontier_wave(
    tmp_path: Path, wave_id: str = "wave-stale-epic-waiting"
):
    """Create stale waiting-on-dependency wave state with empty dispatchables."""
    loop = _build_stale_closed_epic_frontier_wave(tmp_path, wave_id=wave_id)
    loop._set_wave_status(
        LoopState.WAITING_ON_DEPENDENCY,
        BlockerCode.WAITING_ON_DEPENDENCY,
        "No ready tasks: waiting on dependencies for 3 task(s)",
        blocked_details=[
            {
                "beads_id": "bd-bkco.3",
                "title": "Stale child A",
                "unmet_dependencies": ["bd-bkco.2"],
                "dependency_statuses": {"bd-bkco.2": "closed"},
            },
            {
                "beads_id": "bd-bkco.4",
                "title": "Stale child B",
                "unmet_dependencies": ["bd-bkco.2"],
                "dependency_statuses": {"bd-bkco.2": "closed"},
            },
            {
                "beads_id": "bd-bkco.5",
                "title": "Stale child C",
                "unmet_dependencies": ["bd-bkco.2"],
                "dependency_statuses": {"bd-bkco.2": "closed"},
            },
        ],
        dispatchable_tasks=[],
    )
    loop._save_state()
    return loop


def test_no_duplicate_dispatch():
    """P0 fix: Active work not redispatched"""
    scheduler = DxLoopScheduler(cadence_seconds=1)

    # Mark as active
    scheduler.state.mark_dispatched("bd-test-1")

    # Should be active
    assert scheduler.state.is_active("bd-test-1")

    # Mark as completed
    scheduler.state.mark_completed("bd-test-1")

    # Should not be active, should be completed
    assert not scheduler.state.is_active("bd-test-1")
    assert scheduler.state.is_completed("bd-test-1")

    print("✓ No duplicate dispatch works")


def test_notification_first_occurrence():
    """P1 fix: Blocked notifications emit on FIRST occurrence"""
    tracker = LoopStateTracker()

    # First occurrence - should emit
    t1 = tracker.transition(
        LoopState.RUN_BLOCKED, blocker_code=BlockerCode.RUN_BLOCKED, reason="First"
    )
    assert t1 is not None, "First occurrence should emit"

    # Second occurrence (unchanged) - should be suppressed
    t2 = tracker.transition(
        LoopState.RUN_BLOCKED, blocker_code=BlockerCode.RUN_BLOCKED, reason="Second"
    )
    assert t2 is None, "Unchanged second occurrence should be suppressed"

    # Different blocker - should emit
    t3 = tracker.transition(
        LoopState.REVIEW_BLOCKED,
        blocker_code=BlockerCode.REVIEW_BLOCKED,
        reason="Third",
    )
    assert t3 is not None, "Different blocker should emit"

    print("✓ Notification first occurrence works")


def test_state_persistence_round_trip():
    """P1 fix: Save/load is symmetric"""
    # Create manager with data
    manager1 = BeadsWaveManager()
    from dx_loop.beads_integration import BeadsTask

    manager1.tasks = {
        "bd-1": BeadsTask(
            beads_id="bd-1",
            title="Test",
            description="Test description",
            status="open",
            dependencies=[],
            dependents=[],
            priority=2,
        )
    }
    manager1.layers = [["bd-1"]]
    manager1.completed = {"bd-0"}

    # Save
    state_dict = manager1.to_dict()

    # Load
    manager2 = BeadsWaveManager.from_dict(state_dict)

    # Verify symmetric
    assert "bd-1" in manager2.tasks
    assert manager2.tasks["bd-1"].title == "Test"
    assert manager2.tasks["bd-1"].description == "Test description"
    assert manager2.layers == [["bd-1"]]
    assert manager2.completed == {"bd-0"}

    print("✓ State persistence round-trip works")


def test_scheduler_state_persistence():
    """Scheduler state save/load"""
    state1 = SchedulerState()
    state1.active_beads_ids = {"bd-1", "bd-2"}
    state1.completed_beads_ids = {"bd-0"}
    state1.dispatch_count = 5

    # Save
    data = state1.to_dict()

    # Load
    state2 = SchedulerState.from_dict(data)

    # Verify
    assert state2.active_beads_ids == {"bd-1", "bd-2"}
    assert state2.completed_beads_ids == {"bd-0"}
    assert state2.dispatch_count == 5

    print("✓ Scheduler state persistence works")


def test_restart_suppresses_unchanged_blocker_notifications():
    """P1 fix: blocker suppression survives classifier/notification restore"""
    classifier1 = BlockerClassifier()
    notifications1 = NotificationManager()

    blocker1 = classifier1.classify(
        "worktree_missing",
        beads_id="bd-test-1",
        wave_id="wave-test",
    )
    note1 = notifications1.create_notification(blocker1)

    assert note1 is not None, "First blocker occurrence should notify"

    classifier2 = BlockerClassifier.from_dict(classifier1.to_dict())
    notifications2 = NotificationManager.from_dict(notifications1.to_dict())

    blocker2 = classifier2.classify(
        "worktree_missing",
        beads_id="bd-test-1",
        wave_id="wave-test",
    )
    note2 = notifications2.create_notification(blocker2)

    assert blocker2.is_unchanged, "Same blocker after restore should be unchanged"
    assert note2 is None, "Unchanged blocker after restore should be suppressed"

    print("✓ Restart preserves unchanged-blocker suppression")


def test_describe_wave_readiness_reports_dependency_blockers():
    """Dependency-blocked zero-dispatch waves should report unmet dependencies."""
    manager = BeadsWaveManager()
    manager.tasks = {
        "bd-ready": BeadsTask(
            beads_id="bd-ready",
            title="Ready task",
            dependencies=[],
        ),
        "bd-blocked": BeadsTask(
            beads_id="bd-blocked",
            title="Blocked task",
            dependencies=["bd-upstream"],
        ),
    }
    manager.completed = {"bd-ready"}

    readiness = manager.describe_wave_readiness()

    assert readiness.ready == []
    assert readiness.pending_tasks == ["bd-blocked"]
    assert readiness.waiting_on_dependencies == [
        {
            "beads_id": "bd-blocked",
            "title": "Blocked task",
            "unmet_dependencies": ["bd-upstream"],
            "dependency_statuses": {"bd-upstream": "external_or_incomplete"},
        }
    ]

    print("✓ Dependency-blocked waves are classified explicitly")


def test_external_closed_dependency_counts_as_satisfied():
    """Closed non-wave dependencies should make downstream tasks dispatchable."""
    manager = BeadsWaveManager()
    manager.tasks = {
        "bd-blocked": BeadsTask(
            beads_id="bd-blocked",
            title="Blocked task",
            dependencies=["bd-upstream"],
        ),
    }
    manager.dependency_status_cache["bd-upstream"] = "closed"
    manager.layers = [["bd-blocked"]]

    readiness = manager.describe_wave_readiness()

    assert readiness.ready == ["bd-blocked"]
    assert readiness.waiting_on_dependencies == []
    assert manager.get_ready_tasks(0) == ["bd-blocked"]

    print("✓ Closed external dependencies unlock ready work")


def test_unhydrated_tasks_are_not_dispatchable():
    """Tasks with missing Beads detail hydration should stay blocked, not dispatch."""
    manager = BeadsWaveManager()
    manager.tasks = {
        "bd-ready": BeadsTask(
            beads_id="bd-ready",
            title="Ready task",
            dependencies=[],
            details_loaded=True,
        ),
        "bd-unhydrated": BeadsTask(
            beads_id="bd-unhydrated",
            title="Needs hydration",
            dependencies=[],
            details_loaded=False,
            detail_load_error="timeout",
        ),
    }
    manager.layers = [["bd-ready", "bd-unhydrated"]]
    manager.refresh_unhydrated_tasks = lambda timeout_seconds=3: None

    readiness = manager.describe_wave_readiness()

    assert readiness.ready == ["bd-ready"]
    assert readiness.waiting_on_dependencies == [
        {
            "beads_id": "bd-unhydrated",
            "title": "Needs hydration",
            "unmet_dependencies": ["task_metadata_unavailable"],
            "dependency_statuses": {"task_metadata_unavailable": "timeout"},
        }
    ]
    assert manager.get_ready_tasks(0) == ["bd-ready"]

    print("✓ Unhydrated tasks stay blocked instead of dispatching")


def test_from_dict_restores_dependency_status_cache():
    """Persisted dependency status cache should survive save/load round trips."""
    manager1 = BeadsWaveManager()
    manager1.tasks = {
        "bd-blocked": BeadsTask(
            beads_id="bd-blocked",
            title="Blocked task",
            dependencies=["bd-upstream"],
        ),
    }
    manager1.dependency_status_cache = {"bd-upstream": "closed"}
    manager1.layers = [["bd-blocked"]]

    manager2 = BeadsWaveManager.from_dict(manager1.to_dict())

    assert manager2.dependency_status_cache == {"bd-upstream": "closed"}
    assert manager2.get_ready_tasks(0) == ["bd-blocked"]

    print("✓ Dependency status cache persists across resume")


def test_from_dict_restores_dependency_metadata_cache():
    """Cached dependency metadata should survive save/load round trips."""
    manager1 = BeadsWaveManager()
    manager1.dependency_metadata_cache = {
        "bd-upstream": {
            "repo": "affordabot",
            "close_reason": "Closing before merge in PR #342",
            "status": "closed",
            "title": "Affordabot: Upstream",
        }
    }

    manager2 = BeadsWaveManager.from_dict(manager1.to_dict())

    assert manager2.get_dependency_metadata("bd-upstream") == {
        "repo": "affordabot",
        "close_reason": "Closing before merge in PR #342",
        "status": "closed",
        "title": "Affordabot: Upstream",
    }

    print("✓ Dependency metadata cache persists across resume")


def test_backfill_task_repo_from_unique_dependency_metadata():
    """Repo-less tasks should inherit a unique repo from dependency metadata."""
    manager = BeadsWaveManager()
    task = BeadsTask(
        beads_id="bd-child",
        title="Freeze replayable research fixtures",
        dependencies=["bd-parent"],
        repo=None,
    )
    manager.tasks["bd-child"] = task
    manager.dependency_metadata_cache["bd-parent"] = {
        "repo": "affordabot",
        "close_reason": "Closing before merge in PR #342",
        "status": "closed",
        "title": "Affordabot: Curate golden bill matrix",
    }

    manager._backfill_task_repo(task)

    assert task.repo == "affordabot"

    print("✓ Repo-less tasks inherit a unique repo from dependency metadata")


def test_load_task_details_timeout_preserves_skeleton_task(monkeypatch):
    """Timeouts should keep the skeletal task and mark hydration as incomplete."""
    manager = BeadsWaveManager()
    task = BeadsTask(
        beads_id="bd-slow",
        title="Slow task",
        status="open",
        details_loaded=False,
        detail_load_error="not_loaded",
    )

    def fake_run(*args, **kwargs):
        raise subprocess.TimeoutExpired(cmd=kwargs.get("args", args[0]), timeout=3)

    monkeypatch.setattr(subprocess, "run", fake_run)

    hydrated = manager._load_task_details(task, timeout_seconds=3)

    assert hydrated.beads_id == "bd-slow"
    assert hydrated.title == "Slow task"
    assert hydrated.dependencies == []
    assert hydrated.details_loaded is False
    assert hydrated.detail_load_error == "timeout"

    print("✓ Detail timeout preserves skeletal task state")


def test_load_epic_tasks_skips_closed_children(monkeypatch):
    """Closed epic children should count as satisfied, not pending dispatch."""
    manager = BeadsWaveManager()

    def fake_run(cmd, cwd=None, capture_output=None, text=None, timeout=None):
        beads_id = cmd[2]
        if beads_id == "bd-epic":
            payload = [
                {
                    "dependents": [
                        {
                            "id": "bd-closed",
                            "title": "Closed task",
                            "status": "closed",
                            "dependency_type": "parent-child",
                        },
                        {
                            "id": "bd-open",
                            "title": "Open task",
                            "status": "open",
                            "dependency_type": "parent-child",
                        },
                    ]
                }
            ]
        elif beads_id == "bd-open":
            payload = [
                {
                    "title": "Open task",
                    "status": "open",
                    "description": "",
                    "dependencies": [
                        {
                            "id": "bd-closed",
                            "status": "closed",
                            "dependency_type": "blocks",
                        }
                    ],
                }
            ]
        else:
            raise AssertionError(f"unexpected beads id: {beads_id}")

        return subprocess.CompletedProcess(
            cmd, 0, stdout=json.dumps(payload), stderr=""
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    tasks = manager.load_epic_tasks("bd-epic")

    assert [task.beads_id for task in tasks] == ["bd-open"]
    assert "bd-open" in manager.tasks
    assert "bd-closed" not in manager.tasks
    assert "bd-closed" in manager.completed
    assert manager.dependency_status_cache["bd-closed"] == "closed"
    manager.compute_layers()
    assert manager.get_ready_tasks(0) == ["bd-open"]

    print("✓ Closed epic children are treated as already satisfied")


def test_beads_manager_infers_repo_from_title_prefix():
    """Title prefixes should map to the correct canonical repo."""
    manager = BeadsWaveManager()

    assert (
        manager._infer_repo_from_title("Prime Radiant: fix V2 auth")
        == "prime-radiant-ai"
    )
    assert (
        manager._infer_repo_from_title("Agent-skills: harden dx-loop") == "agent-skills"
    )
    assert manager._infer_repo_from_title("Unknown: task") is None

    print("✓ Repo inference works from task title prefixes")


def test_beads_manager_uses_default_repo_for_repo_less_tasks():
    """An explicit default repo should backfill repo-less tasks deterministically."""
    manager = BeadsWaveManager(default_repo="prime-radiant-ai")
    task = BeadsTask(
        beads_id="bd-jx1t.1",
        title="Harden Railway dev build freshness contract",
        dependencies=[],
        repo=None,
    )

    manager._backfill_task_repo(task)

    assert task.repo == "prime-radiant-ai"

    print("✓ Explicit default repo backfills repo-less tasks")


def test_cmd_start_accepts_repo_override(monkeypatch):
    """dx-loop start should pass an explicit repo override into the wave manager."""
    observed = {}

    def fake_load_state(self):
        return False

    def fake_save_state(self):
        return None

    def fake_bootstrap(self, epic_id):
        observed["epic_id"] = epic_id
        observed["default_repo"] = self.beads_manager.default_repo
        return True

    monkeypatch.setattr(DxLoop, "_load_state", fake_load_state)
    monkeypatch.setattr(DxLoop, "_save_state", fake_save_state)
    monkeypatch.setattr(DxLoop, "bootstrap_epic", fake_bootstrap)
    monkeypatch.setattr(DxLoop, "adopt_running_jobs", lambda self: [])
    monkeypatch.setattr(DxLoop, "run_loop", lambda self: True)
    monkeypatch.setattr(dx_loop_script, "_select_wave_state", lambda **kwargs: None)

    args = SimpleNamespace(
        epic="bd-jx1t",
        wave_id="wave-test-repo-override",
        config=None,
        repo="prime-radiant-ai",
    )

    assert cmd_start(args) == 0
    assert observed == {
        "epic_id": "bd-jx1t",
        "default_repo": "prime-radiant-ai",
    }

    print("✓ dx-loop start accepts explicit repo override")


def test_load_state_restores_default_repo_config(tmp_path):
    """Persisted wave config should restore the default repo on restart."""
    wave_id = "wave-default-repo"
    original = DxLoop(wave_id, config={"default_repo": "prime-radiant-ai"})
    original.wave_dir = tmp_path / "waves" / wave_id
    original.state_file = original.wave_dir / "loop_state.json"
    original.beads_manager.tasks = {
        "bd-jx1t.1": BeadsTask(
            beads_id="bd-jx1t.1",
            title="Harden Railway dev build freshness contract",
            repo="prime-radiant-ai",
        )
    }
    original._save_state()

    restored = DxLoop(wave_id)
    restored.wave_dir = original.wave_dir
    restored.state_file = original.state_file

    assert restored._load_state() is True
    assert restored.config["default_repo"] == "prime-radiant-ai"
    assert restored.beads_manager.default_repo == "prime-radiant-ai"

    print("✓ Restart restores persisted default repo config")


def test_save_state_survives_concurrent_surface_writers(tmp_path, monkeypatch):
    """Concurrent saves should use unique temp files and avoid FileNotFoundError."""
    wave_id = "wave-concurrent-save"
    wave_dir = tmp_path / "waves" / wave_id
    loops = []
    for idx in range(2):
        loop = DxLoop(wave_id, config={"cadence_seconds": 0})
        loop.wave_dir = wave_dir
        loop.state_file = wave_dir / "loop_state.json"
        loop.wave_status = {
            "state": "in_progress_healthy",
            "blocker_code": None,
            "reason": f"writer-{idx}",
            "blocked_details": [],
            "dispatchable_tasks": [],
        }
        loops.append(loop)

    barrier = threading.Barrier(2)
    real_write_text = Path.write_text

    def gated_write_text(path_obj, data, *args, **kwargs):
        result = real_write_text(path_obj, data, *args, **kwargs)
        if (
            path_obj.parent == wave_dir
            and path_obj.name.startswith("loop_state")
            and path_obj.suffix == ".tmp"
        ):
            try:
                barrier.wait(timeout=2)
            except threading.BrokenBarrierError:
                pass
        return result

    replace_sources = []
    real_replace = os.replace

    def tracking_replace(src, dst):
        replace_sources.append(Path(src).name)
        return real_replace(src, dst)

    monkeypatch.setattr(Path, "write_text", gated_write_text)
    monkeypatch.setattr(dx_loop_script.os, "replace", tracking_replace)

    errors = []

    def writer(loop: DxLoop):
        try:
            loop._save_state()
        except Exception as exc:
            errors.append(exc)

    threads = [threading.Thread(target=writer, args=(loop,)) for loop in loops]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=5)

    assert all(not thread.is_alive() for thread in threads)
    assert not errors
    assert wave_dir.joinpath("loop_state.json").exists()
    assert len(replace_sources) == 2
    assert len(set(replace_sources)) == 2

    print("✓ Concurrent _save_state writers do not race on temp rename")


def test_extract_implementation_return_from_agent_output():
    """Implementation returns should parse structured tech-lead-handoff blocks."""
    enforcer = PRContractEnforcer()
    output = """
Exploration text

## Tech Lead Review (Implementation Return)
- MODE: implementation_return
- PR_URL: https://github.com/stars-end/prime-radiant-ai/pull/999
- PR_HEAD_SHA: abcdef1234567890abcdef1234567890abcdef12
- BEADS_EPIC: none
- BEADS_SUBTASK: bd-test-1
- BEADS_DEPENDENCIES: bd-upstream

### Validation
- pnpm test: PASS

### Changed Files Summary
- frontend/src/app.tsx: updated test prompt

### Risks / Blockers
- None

### Decisions Needed
- None

### How To Review
1. Inspect the PR
2. Run the validation
"""
    handoff = enforcer.extract_implementation_return(output)

    assert handoff is not None
    assert handoff.mode == "implementation_return"
    assert handoff.pr_url == "https://github.com/stars-end/prime-radiant-ai/pull/999"
    assert handoff.beads_subtask == "bd-test-1"
    assert handoff.validation == ["pnpm test: PASS"]
    assert handoff.changed_files == ["frontend/src/app.tsx: updated test prompt"]
    assert handoff.how_to_review == ["Inspect the PR", "Run the validation"]

    print("✓ Implementation return parsing works")


def test_pr_contract_round_trip_persists_implementation_return():
    """Structured handoffs should survive save/load."""
    enforcer1 = PRContractEnforcer()
    handoff = enforcer1.extract_implementation_return(
        """
## Tech Lead Review (Implementation Return)
- MODE: implementation_return
- PR_URL: https://github.com/stars-end/agent-skills/pull/123
- PR_HEAD_SHA: abcdef1234567890abcdef1234567890abcdef12
- BEADS_EPIC: none
- BEADS_SUBTASK: bd-test-2
- BEADS_DEPENDENCIES: none

### Validation
- pytest: PASS
"""
    )
    assert handoff is not None
    enforcer1.register_implementation_return("bd-test-2", handoff)

    enforcer2 = PRContractEnforcer.from_dict(enforcer1.to_dict())

    restored = enforcer2.get_implementation_return("bd-test-2")
    assert restored is not None
    assert restored.pr_url == "https://github.com/stars-end/agent-skills/pull/123"
    assert enforcer2.has_valid_artifact("bd-test-2")

    print("✓ PR contract persistence includes implementation return")


def test_generated_implement_prompt_uses_handoff_contract():
    """Implement prompts should carry structured handoff instructions."""
    loop = DxLoop("wave-test")
    loop.beads_manager.tasks["bd-test-3"] = BeadsTask(
        beads_id="bd-test-3",
        title="Prime Radiant: improve dx-loop prompts",
        description="Tighten implement prompts so product runs stop wandering.",
        repo="agent-skills",
        dependencies=["bd-upstream"],
    )

    prompt = loop._generate_implement_prompt("bd-test-3")

    assert "tech-lead-handoff" in prompt
    assert "prompt-writing" in prompt
    assert "MODE: implementation_return" in prompt
    assert "Tighten implement prompts" in prompt
    assert "BEADS_DEPENDENCIES: bd-upstream" in prompt

    print("✓ Implement prompt carries structured handoff contract")


def test_generated_review_prompt_consumes_implementation_return():
    """Review prompts should include the captured implementation return."""
    loop = DxLoop("wave-test")
    loop.beads_manager.tasks["bd-test-4"] = BeadsTask(
        beads_id="bd-test-4",
        title="Agent-skills: review prompt test",
        description="Ensure reviewer sees the implementer handoff.",
        repo="agent-skills",
    )
    handoff = PRContractEnforcer().extract_implementation_return(
        """
## Tech Lead Review (Implementation Return)
- MODE: implementation_return
- PR_URL: https://github.com/stars-end/agent-skills/pull/222
- PR_HEAD_SHA: abcdef1234567890abcdef1234567890abcdef12
- BEADS_EPIC: none
- BEADS_SUBTASK: bd-test-4
- BEADS_DEPENDENCIES: none
"""
    )
    assert handoff is not None
    loop.pr_enforcer.register_implementation_return("bd-test-4", handoff)

    prompt = loop._generate_review_prompt(
        "bd-test-4",
        "https://github.com/stars-end/agent-skills/pull/222",
        "abcdef1234567890abcdef1234567890abcdef12",
    )

    assert "dx-loop-review-contract" in prompt
    assert "Implementer Return" in prompt
    assert "MODE: implementation_return" in prompt
    assert "APPROVED" in prompt
    assert ".dx-loop/verdict.json" in prompt

    print(
        "✓ Review prompt consumes implementation return and instructs verdict sidecar"
    )


def test_reconcile_finished_jobs_advances_stale_implement_baton():
    """Restart recovery should ingest a finished implement artifact and move to review."""
    loop = DxLoop("wave-reconcile-finished")
    loop.beads_manager.tasks["bd-test-reconcile"] = BeadsTask(
        beads_id="bd-test-reconcile",
        title="Prime Radiant: recover finished implement outcome",
        repo="prime-radiant-ai",
        dependencies=[],
    )
    loop.baton_manager.start_implement("bd-test-reconcile", run_id="run-123")
    loop.scheduler.state.mark_dispatched("bd-test-reconcile", "implement")
    loop.implement_runner.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="exited_ok",
        exit_code=0,
    )
    loop.implement_runner.extract_pr_artifacts = lambda beads_id: None
    loop.implement_runner.extract_agent_output = lambda beads_id: (
        """
## Tech Lead Review (Implementation Return)
- MODE: implementation_return
- PR_URL: https://github.com/stars-end/prime-radiant-ai/pull/1030
- PR_HEAD_SHA: f4aaa8f48913e6f2e93311767e3ac99669d4e031
- BEADS_EPIC: bd-jx1t
- BEADS_SUBTASK: bd-test-reconcile
- BEADS_DEPENDENCIES: none
"""
    )

    reconciled = loop.reconcile_finished_jobs()

    baton = loop.baton_manager.get_state("bd-test-reconcile")
    assert reconciled == ["bd-test-reconcile"]
    assert baton is not None
    assert baton.phase == BatonPhase.REVIEW
    assert baton.pr_url == "https://github.com/stars-end/prime-radiant-ai/pull/1030"
    assert baton.pr_head_sha == "f4aaa8f48913e6f2e93311767e3ac99669d4e031"
    assert loop.pr_enforcer.has_valid_artifact("bd-test-reconcile")
    assert not loop.scheduler.state.is_active("bd-test-reconcile", "implement")

    print("✓ Restart recovery advances stale implement batons to review")


def test_cmd_start_reuses_existing_active_wave_without_explicit_wave_id(
    tmp_path, monkeypatch, capsys
):
    """start --epic should resume the canonical active wave by default."""
    original_artifact_base = cmd_start.__globals__["ARTIFACT_BASE"]
    cmd_start.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        existing = DxLoop("wave-existing")
        existing.wave_dir = tmp_path / "waves" / "wave-existing"
        existing.state_file = existing.wave_dir / "loop_state.json"
        existing.epic_id = "bd-epic"
        existing.beads_manager.tasks = {
            "bd-test": BeadsTask(
                beads_id="bd-test",
                title="Prime Radiant: existing wave",
                repo="prime-radiant-ai",
                dependencies=[],
            )
        }
        existing._set_wave_status(
            LoopState.IN_PROGRESS_HEALTHY,
            None,
            "Existing active wave",
        )
        existing._save_state()

        monkeypatch.setattr(DxLoop, "adopt_running_jobs", lambda self: [])
        monkeypatch.setattr(DxLoop, "reconcile_finished_jobs", lambda self: [])
        monkeypatch.setattr(DxLoop, "run_loop", lambda self: True)

        rc = cmd_start(
            SimpleNamespace(
                epic="bd-epic",
                wave_id=None,
                config=None,
                repo="prime-radiant-ai",
            )
        )
    finally:
        cmd_start.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    assert (
        "Resuming existing active wave for epic bd-epic: wave-existing" in captured.out
    )
    assert "Wave ID: wave-existing" in captured.out

    print("✓ start --epic resumes the existing active wave by default")


def test_deterministic_implement_failure_transitions_to_retry_state(tmp_path):
    """Quick-fail implement runs should trigger bounded redispatch, not fake healthy state."""
    wave_id = "wave-retry-test"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test-retry": BeadsTask(
            beads_id="bd-test-retry",
            title="Retry task",
            description="Retry deterministic failures cleanly.",
            dependencies=[],
        )
    }

    loop.baton_manager.start_implement("bd-test-retry", run_id="run-1")
    loop.scheduler.state.mark_dispatched("bd-test-retry", "implement")
    loop.runner_adapter.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="exited_err",
        reason_code="stalled_no_progress",
    )
    loop.runner_adapter.extract_agent_output = lambda beads_id: ""
    loop.runner_adapter.extract_pr_artifacts = lambda beads_id: None

    loop._check_implement_progress("bd-test-retry")

    baton = loop.baton_manager.get_state("bd-test-retry")
    assert baton is not None
    assert baton.phase.value == "implement"
    assert baton.attempt == 2
    assert loop.scheduler.state.is_blocked("bd-test-retry")
    assert loop.wave_status["state"] == "deterministic_redispatch_needed"
    assert loop.wave_status["blocker_code"] == "deterministic_redispatch_needed"

    print("✓ Deterministic implement failures enter bounded retry state")


def test_deterministic_implement_failure_exhausts_attempts():
    """Repeated quick-fail implement runs should eventually require a decision."""
    from dx_loop.baton import BatonManager

    baton = BatonManager(max_attempts=2, max_revisions=1)
    baton.start_implement("bd-test")

    state1 = baton.record_implement_retry("bd-test", "monitor_no_rc_file")
    assert state1.phase.value == "implement"
    state2 = baton.record_implement_retry("bd-test", "monitor_no_rc_file")

    assert state2.phase.value == "failed"
    assert state2.metadata["failure_reason"] == "max_attempts_exceeded"

    print("✓ Implement retries are bounded")


def test_status_outputs_waiting_on_dependency_details(tmp_path, capsys):
    """Human-readable status should explain dependency-blocked zero-dispatch waves."""
    wave_id = "wave-operator-status-test"
    loop = DxLoop(wave_id)
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-blocked": BeadsTask(
            beads_id="bd-blocked",
            title="Blocked task",
            dependencies=["bd-upstream"],
        )
    }
    loop.scheduler.state.blocked_beads_ids = {"bd-blocked"}
    loop._set_wave_status(
        LoopState.WAITING_ON_DEPENDENCY,
        BlockerCode.WAITING_ON_DEPENDENCY,
        "No dispatches: waiting on dependencies for 1 task(s)",
        blocked_details=[
            {
                "beads_id": "bd-blocked",
                "title": "Blocked task",
                "unmet_dependencies": ["bd-upstream"],
                "dependency_statuses": {"bd-upstream": "external_or_incomplete"},
            }
        ],
    )
    loop._save_state()

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(SimpleNamespace(wave_id=wave_id, json=False))
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    assert "State: waiting_on_dependency" in captured.out
    assert "Blocker Code: waiting_on_dependency" in captured.out
    assert "Blocked details:" in captured.out
    assert "bd-blocked: bd-upstream" in captured.out

    print("✓ Status output explains dependency blockers")


def test_status_can_resolve_wave_by_beads_id(tmp_path, capsys):
    """status should not require a wave id when the task id is known."""
    wave_id = "wave-task-lookup"
    loop = DxLoop(wave_id)
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.epic_id = "bd-epic"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Agent-facing task",
            repo="prime-radiant-ai",
            dependencies=[],
        )
    }
    loop._set_wave_status(
        LoopState.RUN_BLOCKED,
        BlockerCode.RUN_BLOCKED,
        "Provider at capacity",
        blocked_details=[
            {
                "beads_id": "bd-test",
                "phase": "implement",
                "reason_code": "provider_at_capacity",
            }
        ],
    )
    loop._save_state()

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(
            SimpleNamespace(wave_id=None, epic=None, beads_id="bd-test", json=False)
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    assert "Wave: wave-task-lookup" in captured.out
    assert "Epic: bd-epic" in captured.out
    assert "Task: bd-test" in captured.out
    assert "Task Repo: prime-radiant-ai" in captured.out

    print("✓ Status can resolve the newest wave by beads id")


def test_status_prefers_registered_active_wave_for_beads_id(tmp_path, capsys):
    """Task-oriented status should follow the canonical active wave registry."""
    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        canonical = DxLoop("wave-canonical")
        canonical.wave_dir = tmp_path / "waves" / "wave-canonical"
        canonical.state_file = canonical.wave_dir / "loop_state.json"
        canonical.epic_id = "bd-epic"
        canonical.beads_manager.tasks = {
            "bd-test": BeadsTask(
                beads_id="bd-test",
                title="Canonical task",
                repo="prime-radiant-ai",
                dependencies=[],
            )
        }
        canonical._set_wave_status(
            LoopState.IN_PROGRESS_HEALTHY,
            None,
            "Canonical wave owns this task",
        )
        canonical._save_state()

        newer = DxLoop("wave-newer")
        newer.wave_dir = tmp_path / "waves" / "wave-newer"
        newer.state_file = newer.wave_dir / "loop_state.json"
        newer.epic_id = "bd-epic"
        newer.beads_manager.tasks = {
            "bd-test": BeadsTask(
                beads_id="bd-test",
                title="Competing task",
                repo="prime-radiant-ai",
                dependencies=[],
            )
        }
        newer._set_wave_status(
            LoopState.IN_PROGRESS_HEALTHY,
            None,
            "Competing wave also claims the task",
        )
        newer._save_state()

        dx_loop_script._write_active_epic_registry(
            "bd-epic",
            "wave-canonical",
            artifact_base=tmp_path,
        )

        rc = cmd_status(
            SimpleNamespace(wave_id=None, epic=None, beads_id="bd-test", json=False)
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    assert "Wave: wave-canonical" in captured.out

    print("✓ Status prefers the registered canonical active wave")


def test_status_resolves_epic_when_passed_via_beads_id(tmp_path, capsys):
    """status --beads-id should resolve epic wave state when id is an epic token."""
    wave_id = "wave-epic-token-lookup"
    loop = DxLoop(wave_id)
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.epic_id = "bd-xep1"
    loop.beads_manager.tasks = {
        "bd-child": BeadsTask(
            beads_id="bd-child",
            title="Child task",
            repo="affordabot",
            dependencies=[],
        )
    }
    loop._set_wave_status(
        LoopState.WAITING_ON_DEPENDENCY,
        BlockerCode.WAITING_ON_DEPENDENCY,
        "No dispatches: waiting on dependencies for 1 task(s)",
        blocked_details=[
            {
                "beads_id": "bd-child",
                "phase": "implement",
                "reason_code": "dx_dependency_artifacts_missing",
                "detail": "Upstream dependency missing PR artifacts: bd-iey6",
            }
        ],
    )
    loop._save_state()

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(
            SimpleNamespace(wave_id=None, epic=None, beads_id="bd-xep1", json=False)
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    assert f"Wave: {wave_id}" in captured.out
    assert "Epic: bd-xep1" in captured.out

    print("✓ status resolves epic token passed via --beads-id")


def test_status_missing_wave_reports_epic_token_diagnostics(tmp_path, capsys):
    """Missing-wave surfaces should provide actionable epic-token diagnostics."""
    active_epics = tmp_path / "active-epics"
    active_epics.mkdir(parents=True)
    (active_epics / "bd-xep1.json").write_text(
        json.dumps(
            {
                "epic_id": "bd-xep1",
                "wave_id": "wave-missing",
                "pid": 1234,
                "updated_at": "2026-04-03T00:00:00Z",
            }
        )
    )

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(
            SimpleNamespace(wave_id=None, epic=None, beads_id="bd-xep1", json=False)
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 1
    assert "Wave state not found for bd-xep1" in captured.err
    assert "Active epic registry points to missing wave file" in captured.err

    print("✓ missing-wave diagnostics explain unresolved epic-token lookup")


def test_status_missing_wave_for_first_use_beads_task_is_actionable(
    tmp_path, monkeypatch, capsys
):
    """status --beads-id should guide first-use tasks without persisted wave state."""
    existing = DxLoop("wave-existing")
    existing.wave_dir = tmp_path / "waves" / "wave-existing"
    existing.state_file = existing.wave_dir / "loop_state.json"
    existing.epic_id = "bd-other"
    existing._set_wave_status(
        LoopState.IN_PROGRESS_HEALTHY,
        None,
        "Existing wave for a different epic",
    )
    existing._save_state()

    def fake_run(cmd, **kwargs):
        assert cmd == ["bd", "show", "bd-epyeg", "--json"]
        payload = [
            {
                "id": "bd-epyeg",
                "dependencies": [
                    {
                        "id": "bd-5w5o",
                        "dependency_type": "parent-child",
                    }
                ],
            }
        ]
        return subprocess.CompletedProcess(
            cmd, 0, stdout=json.dumps(payload), stderr=""
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(
            SimpleNamespace(wave_id=None, epic=None, beads_id="bd-epyeg", json=False)
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 1
    assert "Wave state not found for bd-epyeg" in captured.err
    assert "Blocker Class: control_plane_missing_wave_state" in captured.err
    assert "Resolved parent epic: bd-5w5o" in captured.err
    assert "`dx-loop start --epic bd-5w5o`" in captured.err
    assert "`dx-loop status --beads-id bd-epyeg`" in captured.err

    print("✓ status first-use missing-wave diagnostics are actionable")


def test_explain_missing_wave_for_first_use_beads_task_is_actionable(
    tmp_path, monkeypatch, capsys
):
    """explain --beads-id should guide first-use tasks without persisted wave state."""

    def fake_run(cmd, **kwargs):
        assert cmd == ["bd", "show", "bd-epyeg", "--json"]
        payload = [
            {
                "id": "bd-epyeg",
                "dependencies": [
                    {
                        "id": "bd-5w5o",
                        "dependency_type": "parent-child",
                    }
                ],
            }
        ]
        return subprocess.CompletedProcess(
            cmd, 0, stdout=json.dumps(payload), stderr=""
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    original_artifact_base = cmd_explain.__globals__["ARTIFACT_BASE"]
    cmd_explain.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_explain(SimpleNamespace(wave_id=None, epic=None, beads_id="bd-epyeg"))
    finally:
        cmd_explain.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 1
    assert "Wave state not found for bd-epyeg" in captured.err
    assert "Blocker Class: control_plane_missing_wave_state" in captured.err
    assert "Resolved parent epic: bd-5w5o" in captured.err
    assert "`dx-loop start --epic bd-5w5o`" in captured.err

    print("✓ explain first-use missing-wave diagnostics are actionable")


def test_missing_wave_diagnostics_for_explicit_wave_id_remains_specific(
    tmp_path, capsys
):
    """Explicit --wave-id misses should remain specific and not use first-use guidance."""
    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(
            SimpleNamespace(
                wave_id="wave-does-not-exist", epic=None, beads_id=None, json=False
            )
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 1
    assert "Wave state not found for wave-does-not-exist" in captured.err
    assert "No state file exists at:" in captured.err
    assert "Blocker Class: control_plane_missing_wave_state" not in captured.err

    print("✓ explicit wave-id diagnostics remain unchanged")


def test_explain_classifies_review_blocked_as_product(tmp_path, capsys):
    """explain should classify review-blocked waves as product work."""
    wave_id = "wave-explain-product"
    loop = DxLoop(wave_id)
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.epic_id = "bd-epic"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Needs product revision",
            dependencies=[],
        )
    }
    loop._set_wave_status(
        LoopState.REVIEW_BLOCKED,
        BlockerCode.REVIEW_BLOCKED,
        "Reviewer requested changes",
        blocked_details=[
            {
                "beads_id": "bd-test",
                "phase": "review",
                "reason_code": "revision_required",
                "detail": "PR needs a narrow repair",
            }
        ],
    )
    loop._save_state()

    original_artifact_base = cmd_explain.__globals__["ARTIFACT_BASE"]
    cmd_explain.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_explain(SimpleNamespace(wave_id=None, epic=None, beads_id="bd-test"))
    finally:
        cmd_explain.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    assert "Surface: product" in captured.out
    assert "Next Action: Address review findings" in captured.out

    print("✓ Explain classifies review-blocked waves as product")


def test_explain_classifies_run_blocked_as_control_plane(tmp_path, capsys):
    """explain should classify startup/runner failures as control-plane work."""
    wave_id = "wave-explain-control"
    loop = DxLoop(wave_id)
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.epic_id = "bd-epic"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Blocked by startup",
            dependencies=[],
        )
    }
    loop._set_wave_status(
        LoopState.RUN_BLOCKED,
        BlockerCode.RUN_BLOCKED,
        "Provider at capacity",
        blocked_details=[
            {
                "beads_id": "bd-test",
                "phase": "implement",
                "reason_code": "provider_at_capacity",
            }
        ],
    )
    loop._save_state()

    original_artifact_base = cmd_explain.__globals__["ARTIFACT_BASE"]
    cmd_explain.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_explain(
            SimpleNamespace(wave_id=None, epic="bd-epic", beads_id="bd-test")
        )
    finally:
        cmd_explain.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    assert "Surface: control_plane" in captured.out
    assert "Next Action: Inspect dx-loop/dx-runner startup" in captured.out

    print("✓ Explain classifies run-blocked waves as control-plane")


def test_status_reconciles_stale_closed_active_review_task(
    tmp_path, monkeypatch, capsys
):
    """status --json should clear stale active review state when Beads reports closed."""
    _build_stale_closed_review_wave(tmp_path, wave_id="wave-stale-status")

    def fake_run(cmd, **kwargs):
        if cmd[:2] == ["bd", "show"] and cmd[2] == "bd-bkco.2":
            payload = [
                {
                    "id": "bd-bkco.2",
                    "title": "Merged task",
                    "status": "closed",
                    "close_reason": "Merged in PR #344",
                }
            ]
            return subprocess.CompletedProcess(
                cmd, 0, stdout=json.dumps(payload), stderr=""
            )
        raise AssertionError(f"unexpected command: {cmd}")

    monkeypatch.setattr(subprocess, "run", fake_run)

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(
            SimpleNamespace(wave_id=None, epic="bd-bkco", beads_id=None, json=True)
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    state = json.loads(captured.out)

    assert "bd-bkco.2:review" not in state["scheduler_state"]["active_beads_ids"]
    assert "bd-bkco.2" in state["scheduler_state"]["completed_beads_ids"]
    assert "bd-bkco.2" in state["beads_manager"]["completed"]
    assert "bd-bkco.2" not in state["wave_status"]["dispatchable_tasks"]
    assert "bd-bkco.3" in state["wave_status"]["dispatchable_tasks"]
    assert state["baton_states"]["bd-bkco.2"]["phase"] == "complete"

    print("✓ status --json reconciles stale closed active review task")


def test_explain_reconciles_stale_closed_task_and_avoids_continue_monitoring(
    tmp_path, monkeypatch, capsys
):
    """explain should not report passive monitoring after stale close reconciliation."""
    _build_stale_closed_review_wave(tmp_path, wave_id="wave-stale-explain")

    def fake_run(cmd, **kwargs):
        if cmd[:2] == ["bd", "show"] and cmd[2] == "bd-bkco.2":
            payload = [
                {
                    "id": "bd-bkco.2",
                    "title": "Merged task",
                    "status": "closed",
                    "close_reason": "Merged in PR #344",
                }
            ]
            return subprocess.CompletedProcess(
                cmd, 0, stdout=json.dumps(payload), stderr=""
            )
        raise AssertionError(f"unexpected command: {cmd}")

    monkeypatch.setattr(subprocess, "run", fake_run)

    original_artifact_base = cmd_explain.__globals__["ARTIFACT_BASE"]
    cmd_explain.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_explain(SimpleNamespace(wave_id=None, epic="bd-bkco", beads_id=None))
    finally:
        cmd_explain.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    assert (
        "Next Action: Resume or restart dx-loop to dispatch ready tasks."
        in captured.out
    )
    assert (
        "Continue monitoring; no blocking action is currently required."
        not in captured.out
    )

    print("✓ explain reports actionable next step after stale close reconciliation")


def test_status_retires_stale_dispatch_frontier_when_epic_closed(
    tmp_path, monkeypatch, capsys
):
    """status --json should retire stale dispatch frontier when parent epic is closed."""
    _build_stale_closed_epic_frontier_wave(tmp_path, wave_id="wave-stale-epic-closed")

    def fake_run(cmd, **kwargs):
        if cmd[:2] == ["bd", "show"] and cmd[2] == "bd-bkco":
            payload = [
                {
                    "id": "bd-bkco",
                    "status": "closed",
                    "dependents": [
                        {
                            "id": "bd-bkco.2",
                            "dependency_type": "parent-child",
                            "title": "Merged prerequisite",
                            "status": "closed",
                            "close_reason": "Merged via PR #344",
                        },
                        {
                            "id": "bd-bkco.3",
                            "dependency_type": "parent-child",
                            "title": "Stale child A",
                            "status": "closed",
                            "close_reason": "Closing before merge in PR #347",
                        },
                        {
                            "id": "bd-bkco.4",
                            "dependency_type": "parent-child",
                            "title": "Stale child B",
                            "status": "closed",
                            "close_reason": "Closing before merge in PR #348",
                        },
                        {
                            "id": "bd-bkco.5",
                            "dependency_type": "parent-child",
                            "title": "Stale child C",
                            "status": "closed",
                            "close_reason": "Closing before merge in PR #349",
                        },
                        {
                            "id": "bd-bkco.6",
                            "dependency_type": "parent-child",
                            "title": "Stale child D",
                            "status": "closed",
                            "close_reason": "Closing before merge in PR #350",
                        },
                    ],
                }
            ]
            return subprocess.CompletedProcess(
                cmd, 0, stdout=json.dumps(payload), stderr=""
            )
        raise AssertionError(f"unexpected command: {cmd}")

    monkeypatch.setattr(subprocess, "run", fake_run)

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(
            SimpleNamespace(wave_id=None, epic="bd-bkco", beads_id=None, json=True)
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    state = json.loads(captured.out)

    assert state["wave_status"]["state"] == "completed"
    assert state["wave_status"]["dispatchable_tasks"] == []
    assert "closed in Beads" in state["wave_status"]["reason"]
    assert "bd-bkco.3" in state["beads_manager"]["completed"]
    assert "bd-bkco.4" in state["beads_manager"]["completed"]
    assert "bd-bkco.5" in state["beads_manager"]["completed"]
    assert "bd-bkco.6" in state["beads_manager"]["completed"]
    assert state["beads_manager"]["tasks"]["bd-bkco.3"]["status"] == "closed"
    assert state["beads_manager"]["tasks"]["bd-bkco.4"]["status"] == "closed"
    assert state["beads_manager"]["tasks"]["bd-bkco.5"]["status"] == "closed"
    assert state["beads_manager"]["tasks"]["bd-bkco.6"]["status"] == "closed"

    print("✓ status retires stale dispatch frontier for closed epic")


def test_status_retires_closed_epic_waiting_wave_with_empty_dispatchable(
    tmp_path, monkeypatch, capsys
):
    """Closed-epic retirement should not depend on persisted dispatchable tasks."""
    _build_stale_waiting_closed_epic_frontier_wave(
        tmp_path, wave_id="wave-stale-epic-waiting-empty"
    )
    calls = {"epic_refresh": 0}

    def fake_run(cmd, **kwargs):
        if cmd[:2] == ["bd", "show"] and cmd[2] == "bd-bkco":
            calls["epic_refresh"] += 1
            payload = [
                {
                    "id": "bd-bkco",
                    "status": "closed",
                    "dependents": [
                        {
                            "id": "bd-bkco.2",
                            "dependency_type": "parent-child",
                            "title": "Merged prerequisite",
                            "status": "closed",
                            "close_reason": "Merged via PR #344",
                        },
                        {
                            "id": "bd-bkco.3",
                            "dependency_type": "parent-child",
                            "title": "Stale child A",
                            "status": "closed",
                            "close_reason": "Closing before merge in PR #347",
                        },
                        {
                            "id": "bd-bkco.4",
                            "dependency_type": "parent-child",
                            "title": "Stale child B",
                            "status": "closed",
                            "close_reason": "Closing before merge in PR #348",
                        },
                        {
                            "id": "bd-bkco.5",
                            "dependency_type": "parent-child",
                            "title": "Stale child C",
                            "status": "closed",
                            "close_reason": "Closing before merge in PR #349",
                        },
                        {
                            "id": "bd-bkco.6",
                            "dependency_type": "parent-child",
                            "title": "Stale child D",
                            "status": "closed",
                            "close_reason": "Closing before merge in PR #350",
                        },
                    ],
                }
            ]
            return subprocess.CompletedProcess(
                cmd, 0, stdout=json.dumps(payload), stderr=""
            )
        raise AssertionError(f"unexpected command: {cmd}")

    monkeypatch.setattr(subprocess, "run", fake_run)

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(
            SimpleNamespace(wave_id=None, epic="bd-bkco", beads_id=None, json=True)
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    state = json.loads(captured.out)

    assert calls["epic_refresh"] == 1
    assert state["wave_status"]["state"] == "completed"
    assert state["wave_status"]["dispatchable_tasks"] == []
    assert "closed in Beads" in state["wave_status"]["reason"]
    assert state["wave_status"]["blocker_code"] is None
    assert "bd-bkco.3" in state["beads_manager"]["completed"]
    assert state["beads_manager"]["tasks"]["bd-bkco.3"]["status"] == "closed"

    print("✓ status retires closed-epic waiting wave with empty dispatchables")


def test_explain_reports_closed_epic_as_retired(tmp_path, monkeypatch, capsys):
    """explain should be truthful when a stale wave belongs to a closed epic."""
    _build_stale_closed_epic_frontier_wave(
        tmp_path, wave_id="wave-stale-epic-explain-closed"
    )

    def fake_run(cmd, **kwargs):
        if cmd[:2] == ["bd", "show"] and cmd[2] == "bd-bkco":
            payload = [
                {
                    "id": "bd-bkco",
                    "status": "closed",
                    "dependents": [
                        {
                            "id": "bd-bkco.3",
                            "dependency_type": "parent-child",
                            "title": "Stale child A",
                            "status": "closed",
                        }
                    ],
                }
            ]
            return subprocess.CompletedProcess(
                cmd, 0, stdout=json.dumps(payload), stderr=""
            )
        raise AssertionError(f"unexpected command: {cmd}")

    monkeypatch.setattr(subprocess, "run", fake_run)

    original_artifact_base = cmd_explain.__globals__["ARTIFACT_BASE"]
    cmd_explain.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_explain(SimpleNamespace(wave_id=None, epic="bd-bkco", beads_id=None))
    finally:
        cmd_explain.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    assert "State: completed" in captured.out
    assert (
        "Reason: Epic bd-bkco is closed in Beads; stale wave cache retired"
        in captured.out
    )
    assert (
        "Next Action: No action required: epic is already closed and this wave is retired."
        in captured.out
    )
    assert "dispatch ready tasks" not in captured.out

    print("✓ explain reports closed epic wave as retired")


def test_status_reconciles_stale_closed_task_with_surface_timeout_budget(
    tmp_path, monkeypatch, capsys
):
    """status reconciliation should use a longer Beads timeout than cadence polling."""
    _build_stale_closed_review_wave(tmp_path, wave_id="wave-stale-timeout")

    def fake_run(cmd, **kwargs):
        if cmd[:2] == ["bd", "show"] and cmd[2] == "bd-bkco.2":
            timeout = kwargs.get("timeout")
            if timeout < dx_loop_script.SURFACE_BEADS_TIMEOUT_SECONDS:
                raise subprocess.TimeoutExpired(cmd, timeout)
            payload = [
                {
                    "id": "bd-bkco.2",
                    "title": "Merged task",
                    "status": "closed",
                    "close_reason": "Merged in PR #344",
                }
            ]
            return subprocess.CompletedProcess(
                cmd, 0, stdout=json.dumps(payload), stderr=""
            )
        raise AssertionError(f"unexpected command: {cmd}")

    monkeypatch.setattr(subprocess, "run", fake_run)

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(
            SimpleNamespace(wave_id=None, epic="bd-bkco", beads_id=None, json=True)
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    state = json.loads(captured.out)

    assert state["baton_states"]["bd-bkco.2"]["phase"] == "complete"
    assert "bd-bkco.2" not in state["wave_status"]["dispatchable_tasks"]
    assert "bd-bkco.3" in state["wave_status"]["dispatchable_tasks"]

    print("✓ status reconciliation uses longer Beads timeout budget")


def test_status_reconciles_stale_closed_failed_blocked_task(
    tmp_path, monkeypatch, capsys
):
    """status --json should reconcile externally closed tasks stuck in failed/blocked state."""
    wave_id = "wave-stale-failed-blocked"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.epic_id = "bd-bkco"
    loop.beads_manager.tasks = {
        "bd-bkco.2": BeadsTask(
            beads_id="bd-bkco.2",
            title="Previously revision-blocked task",
            repo="agent-skills",
            dependencies=[],
            status="open",
            details_loaded=True,
        ),
        "bd-bkco.3": BeadsTask(
            beads_id="bd-bkco.3",
            title="Downstream task",
            repo="agent-skills",
            dependencies=["bd-bkco.2"],
            status="open",
            details_loaded=True,
        ),
    }
    loop.beads_manager.layers = [["bd-bkco.2"], ["bd-bkco.3"]]

    loop.baton_manager.start_implement("bd-bkco.2")
    loop.baton_manager.complete_implement(
        "bd-bkco.2", pr_url="https://example/pr/344", pr_head_sha="a" * 40
    )
    loop.baton_manager.start_review("bd-bkco.2", run_id="review-run-stale")
    loop.baton_manager.complete_review(
        "bd-bkco.2",
        ReviewVerdict.REVISION_REQUIRED,
        "Needs another revision",
    )
    loop.baton_manager.baton_states["bd-bkco.2"].revision_count = 3
    loop.baton_manager.baton_states["bd-bkco.2"].metadata["failure_reason"] = (
        "max_revisions_exceeded"
    )
    loop.scheduler.state.mark_blocked("bd-bkco.2")
    loop._set_wave_status(
        LoopState.REVIEW_BLOCKED,
        BlockerCode.REVIEW_BLOCKED,
        "Task stuck at max revisions",
        blocked_details=[
            {
                "beads_id": "bd-bkco.2",
                "phase": "review",
                "reason_code": "max_revisions_exceeded",
            }
        ],
        dispatchable_tasks=["bd-bkco.2"],
    )
    loop._save_state()

    def fake_run(cmd, **kwargs):
        if cmd[:2] == ["bd", "show"] and cmd[2] == "bd-bkco.2":
            payload = [
                {
                    "id": "bd-bkco.2",
                    "title": "Previously revision-blocked task",
                    "status": "closed",
                    "close_reason": "Merged in PR #344",
                }
            ]
            return subprocess.CompletedProcess(
                cmd, 0, stdout=json.dumps(payload), stderr=""
            )
        raise AssertionError(f"unexpected command: {cmd}")

    monkeypatch.setattr(subprocess, "run", fake_run)

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(
            SimpleNamespace(wave_id=None, epic="bd-bkco", beads_id=None, json=True)
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    state = json.loads(captured.out)

    assert "bd-bkco.2" in state["scheduler_state"]["completed_beads_ids"]
    assert "bd-bkco.2" not in state["scheduler_state"]["blocked_beads_ids"]
    assert "bd-bkco.2" in state["beads_manager"]["completed"]
    assert state["baton_states"]["bd-bkco.2"]["phase"] == "complete"
    assert "bd-bkco.2" not in state["wave_status"]["dispatchable_tasks"]
    assert "bd-bkco.3" in state["wave_status"]["dispatchable_tasks"]

    print("✓ status reconciles stale closed failed/blocked task")


def test_status_reconcile_excludes_scheduler_blocked_dispatchables(
    tmp_path, monkeypatch, capsys
):
    """status reconciliation should not advertise scheduler-blocked tasks as ready."""
    wave_id = "wave-stale-blocked-surface"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.epic_id = "bd-bkco"
    loop.beads_manager.tasks = {
        "bd-bkco.2": BeadsTask(
            beads_id="bd-bkco.2",
            title="Blocked task",
            repo="agent-skills",
            dependencies=[],
            status="open",
            details_loaded=True,
        ),
        "bd-bkco.3": BeadsTask(
            beads_id="bd-bkco.3",
            title="Downstream task",
            repo="agent-skills",
            dependencies=["bd-bkco.2"],
            status="open",
            details_loaded=True,
        ),
    }
    loop.beads_manager.layers = [["bd-bkco.2"], ["bd-bkco.3"]]
    loop.scheduler.state.mark_blocked("bd-bkco.2")
    loop._set_wave_status(
        LoopState.IN_PROGRESS_HEALTHY,
        None,
        "Dispatching 1 task(s)",
        dispatchable_tasks=["bd-bkco.2"],
    )
    loop._save_state()

    monkeypatch.setattr(DxLoop, "_refresh_beads_truth", lambda self, **kwargs: [])

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(
            SimpleNamespace(wave_id=None, epic="bd-bkco", beads_id=None, json=True)
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    state = json.loads(captured.out)

    assert state["wave_status"]["state"] == "waiting_on_dependency"
    assert state["wave_status"]["blocker_code"] == "waiting_on_dependency"
    assert state["wave_status"]["dispatchable_tasks"] == []
    assert state["wave_status"]["blocked_details"][0]["beads_id"] == "bd-bkco.2"
    assert "blocked before runner start" in state["wave_status"]["reason"]

    print("✓ status reconciliation excludes blocked tasks from dispatchable set")


def test_status_reconcile_preserves_blocked_state_without_baton(
    tmp_path, monkeypatch, capsys
):
    """status reconciliation should stay blocked when scheduler is blocked but baton is empty."""
    wave_id = "wave-blocked-no-baton"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.epic_id = None
    loop.beads_manager.tasks = {
        "bd-blocked": BeadsTask(
            beads_id="bd-blocked",
            title="Blocked before runner start",
            repo="affordabot",
            dependencies=[],
            status="open",
            details_loaded=True,
        )
    }
    loop.beads_manager.layers = [["bd-blocked"]]
    loop.scheduler.state.mark_blocked("bd-blocked")
    loop._set_wave_status(
        LoopState.WAITING_ON_DEPENDENCY,
        BlockerCode.WAITING_ON_DEPENDENCY,
        "No dispatches: waiting on dependency PR artifacts for 1 task(s)",
        blocked_details=[
            {
                "beads_id": "bd-blocked",
                "phase": "implement",
                "reason_code": "dx_dependency_artifacts_missing",
                "detail": "Upstream dependency missing PR artifacts: bd-iey6",
                "unmet_dependencies": ["bd-iey6"],
            }
        ],
    )
    loop._save_state()

    monkeypatch.setattr(DxLoop, "_refresh_beads_truth", lambda self, **kwargs: [])

    original_artifact_base = cmd_status.__globals__["ARTIFACT_BASE"]
    cmd_status.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        rc = cmd_status(
            SimpleNamespace(wave_id=None, epic=None, beads_id="bd-blocked", json=True)
        )
    finally:
        cmd_status.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 0
    state = json.loads(captured.out)
    assert state["wave_status"]["state"] == "waiting_on_dependency"
    assert state["wave_status"]["blocker_code"] == "waiting_on_dependency"
    assert state["wave_status"]["dispatchable_tasks"] == []
    assert "blocked before runner start" in state["wave_status"]["reason"]

    print("✓ status reconciliation preserves blocked no-baton state")


def test_cmd_start_refuses_second_active_wave_for_same_epic(tmp_path, capsys):
    """Starting a second live wave for the same epic should fail fast."""
    original_artifact_base = cmd_start.__globals__["ARTIFACT_BASE"]
    cmd_start.__globals__["ARTIFACT_BASE"] = tmp_path
    try:
        existing = DxLoop("wave-existing")
        existing.wave_dir = tmp_path / "waves" / "wave-existing"
        existing.state_file = existing.wave_dir / "loop_state.json"
        existing.epic_id = "bd-jx1t"
        existing.beads_manager.tasks = {
            "bd-jx1t.1": BeadsTask(
                beads_id="bd-jx1t.1",
                title="Existing active task",
                repo="prime-radiant-ai",
                dependencies=[],
            )
        }
        existing._set_wave_status(
            LoopState.IN_PROGRESS_HEALTHY,
            None,
            "Existing active wave",
        )
        existing._save_state()

        rc = cmd_start(
            SimpleNamespace(
                epic="bd-jx1t",
                wave_id="wave-duplicate",
                config=None,
                repo="prime-radiant-ai",
            )
        )
    finally:
        cmd_start.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 1
    assert "Active wave already exists for epic bd-jx1t: wave-existing" in captured.err

    print("✓ cmd_start refuses a second active wave for the same epic")


def test_start_prints_wave_id_before_bootstrap_failure(monkeypatch, tmp_path, capsys):
    """Fresh starts should expose the generated wave id before bootstrap returns."""
    wave_id = "wave-visible-before-bootstrap"
    original_artifact_base = cmd_start.__globals__["ARTIFACT_BASE"]
    original_dxloop_init = DxLoop.__init__
    original_bootstrap_epic = DxLoop.bootstrap_epic
    original_save_state = DxLoop._save_state

    def fake_init(self, wave_id_arg, config=None):
        original_dxloop_init(self, wave_id_arg, config=config)
        self.wave_dir = tmp_path / "waves" / wave_id_arg
        self.state_file = self.wave_dir / "loop_state.json"

    def fake_bootstrap(self, epic_id):
        return False

    monkeypatch.setattr(dx_loop_script, "ARTIFACT_BASE", tmp_path)
    monkeypatch.setattr(DxLoop, "__init__", fake_init)
    monkeypatch.setattr(DxLoop, "bootstrap_epic", fake_bootstrap)

    try:
        rc = cmd_start(SimpleNamespace(epic="bd-epic", wave_id=wave_id, config=None))
    finally:
        monkeypatch.setattr(DxLoop, "__init__", original_dxloop_init)
        monkeypatch.setattr(DxLoop, "bootstrap_epic", original_bootstrap_epic)
        monkeypatch.setattr(DxLoop, "_save_state", original_save_state)
        cmd_start.__globals__["ARTIFACT_BASE"] = original_artifact_base

    captured = capsys.readouterr()
    assert rc == 1
    assert f"Wave ID: {wave_id}" in captured.out
    assert f"Inspect with: dx-loop status --wave-id {wave_id}" in captured.out
    assert (tmp_path / "waves" / wave_id / "loop_state.json").exists()

    print("✓ Fresh starts expose wave id before bootstrap failure")


def test_run_loop_exits_when_initial_frontier_is_fully_blocked(tmp_path):
    """A zero-dispatch blocked start should persist state and exit promptly."""
    wave_id = "wave-blocked-at-start"
    loop = DxLoop(wave_id, config={"cadence_seconds": 1})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-blocked-1": BeadsTask(
            beads_id="bd-blocked-1",
            title="Blocked task 1",
            dependencies=["bd-upstream"],
        ),
        "bd-blocked-2": BeadsTask(
            beads_id="bd-blocked-2",
            title="Blocked task 2",
            dependencies=["bd-blocked-1"],
        ),
    }
    loop.beads_manager.layers = [["bd-blocked-1"], ["bd-blocked-2"]]

    assert loop.run_loop(max_iterations=2) is True

    state = json.loads(loop.state_file.read_text())
    assert state["scheduler_state"]["dispatch_count"] == 0
    assert state["wave_status"]["state"] == "waiting_on_dependency"
    assert (
        state["wave_status"]["reason"]
        == "Initial frontier blocked with 2 task(s); exiting without resident loop"
    )
    assert len(state["wave_status"]["blocked_details"]) == 2

    print("✓ Blocked-at-start waves exit promptly")


def test_dx_ensure_bins_links_dx_loop(tmp_path):
    """dx-loop should be linked into the canonical operator bin dir and execute."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()

    result = subprocess.run(
        ["bash", str(REPO_ROOT / "scripts" / "dx-ensure-bins.sh")],
        env={
            "PATH": "/usr/bin:/bin",
            "HOME": str(tmp_path),
            "AGENTS_ROOT": str(REPO_ROOT),
            "BIN_DIR": str(bin_dir),
        },
        capture_output=True,
        text=True,
        check=True,
    )

    assert "ensured ~/bin tools" in result.stdout
    linked = bin_dir / "dx-loop"
    assert linked.is_symlink()
    assert linked.resolve().samefile(REPO_ROOT / "scripts" / "dx-loop")

    version = subprocess.run(
        [str(linked), "--version"],
        env={
            "PATH": f"{bin_dir}:/usr/bin:/bin",
            "HOME": str(tmp_path),
        },
        capture_output=True,
        text=True,
        check=True,
    )
    version_match = version.stdout.strip()
    assert version_match.startswith("dx-loop "), (
        f"Unexpected version output: {version_match}"
    )

    print("✓ dx-loop canonical entrypoint is linked")


def test_runner_adapter_uses_homebrew_bash_on_macos(monkeypatch):
    """macOS launches should wrap dx-runner with a bash 4+ entrypoint."""
    adapter = RunnerAdapter(provider="opencode")

    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("shutil.which", lambda name: "/Users/fengning/bin/dx-runner")
    monkeypatch.setattr(
        adapter, "_preferred_bash", lambda: Path("/opt/homebrew/bin/bash")
    )

    result = adapter._build_dx_runner_command(["status"])

    assert result.ok is True
    assert result.command == [
        "/opt/homebrew/bin/bash",
        str(adapter._dx_runner_script_path()),
        "status",
    ]

    print("✓ RunnerAdapter wraps dx-runner with Homebrew bash on macOS")


def test_runner_adapter_prefers_local_dx_runner_script_over_path(monkeypatch, tmp_path):
    """dx-loop should use the co-located dx-runner script, not a stale PATH binary."""
    adapter = RunnerAdapter(provider="opencode")
    local_runner = tmp_path / "dx-runner"
    local_runner.write_text("#!/usr/bin/env bash\n")

    monkeypatch.setattr(adapter, "_dx_runner_script_path", lambda: local_runner)
    monkeypatch.setattr("platform.system", lambda: "Linux")
    monkeypatch.setattr("shutil.which", lambda name: "/Users/fengning/bin/dx-runner")

    result = adapter._build_dx_runner_command(["status"])

    assert result.ok is True
    assert result.command == [str(local_runner), "status"]

    print("✓ RunnerAdapter prefers the local dx-runner script over PATH")


def test_runner_adapter_reports_shell_preflight_failure_without_bash4(monkeypatch):
    """macOS should fail explicitly when no bash 4+ entrypoint is available."""
    adapter = RunnerAdapter(provider="opencode")

    monkeypatch.setattr("platform.system", lambda: "Darwin")
    monkeypatch.setattr("shutil.which", lambda name: "/Users/fengning/bin/dx-runner")
    monkeypatch.setattr(adapter, "_preferred_bash", lambda: None)

    result = adapter.start("bd-test", Path("/tmp/test.prompt"))

    assert result.ok is False
    assert result.reason_code == "dx_runner_shell_preflight_failed"
    assert "bash >= 4" in (result.detail or "")

    print("✓ RunnerAdapter surfaces shell preflight failure explicitly")


def test_runner_adapter_accepts_timeout_when_runner_state_exists(monkeypatch):
    """A slow dx-runner start should still count as success if the job is live."""
    adapter = RunnerAdapter(provider="opencode")
    timeout_result = RunnerStartResult(
        ok=False,
        returncode=124,
        reason_code="dx_runner_start_timeout",
        detail="dx-runner timed out after 30s",
        command=["dx-runner", "start"],
    )

    monkeypatch.setattr(
        adapter, "_run_dx_runner", lambda *args, **kwargs: timeout_result
    )
    monkeypatch.setattr(
        adapter,
        "check",
        lambda beads_id: RunnerTaskState(
            beads_id=beads_id,
            state="healthy",
            reason_code="recent_log_activity",
        ),
    )

    result = adapter.start("bd-test", Path("/tmp/test.prompt"))

    assert result.ok is True
    assert result.reason_code == "dx_runner_start_timeout_handoff"

    print("✓ RunnerAdapter treats timeout as success when the job is already live")


def test_runner_adapter_check_parses_json_after_banner(monkeypatch):
    """check/report should tolerate canonical banner text before JSON payloads."""
    adapter = RunnerAdapter(provider="opencode")

    banner_json = """
━━━━━━━━ reminder ━━━━━━━━
Use worktrees.
{"state":"exited_ok","reason_code":"process_exit_with_rc","pr_url":"https://example/pull/1","pr_head_sha":"abc123"}
"""
    monkeypatch.setattr(
        adapter,
        "_run_dx_runner",
        lambda *args, **kwargs: RunnerStartResult(
            ok=True,
            returncode=0,
            stdout=banner_json,
            stderr="",
            command=["dx-runner", "check"],
        ),
    )

    state = adapter.check("bd-test")
    report = adapter.report("bd-test")

    assert state is not None
    assert state.state == "exited_ok"
    assert state.has_pr_artifacts is True
    assert state.pr_url == "https://example/pull/1"
    assert report is not None
    assert report["pr_head_sha"] == "abc123"

    print("✓ RunnerAdapter parses JSON payloads after banner text")


def test_runner_task_state_treats_terminal_variants_as_complete():
    """dx-loop should not strand on terminal runner states beyond exited_ok/exited_err."""
    assert RunnerTaskState(beads_id="bd-test", state="stopped").is_complete() is True
    assert (
        RunnerTaskState(beads_id="bd-test", state="no_op_success").is_complete() is True
    )

    print("✓ RunnerTaskState treats stopped/no_op_success as terminal")


def test_runner_adapter_uses_canonical_bd_cwd(monkeypatch, tmp_path):
    """All dx-runner subprocesses should run from the canonical Beads repo cwd."""
    adapter = RunnerAdapter(provider="opencode", beads_repo_path=tmp_path / "bd")

    monkeypatch.setattr("platform.system", lambda: "Linux")
    local_runner = tmp_path / "dx-runner"
    local_runner.write_text("#!/usr/bin/env bash\n")
    monkeypatch.setattr(adapter, "_dx_runner_script_path", lambda: local_runner)

    captured = {}

    def fake_run(cmd, **kwargs):
        captured["cmd"] = cmd
        captured["cwd"] = kwargs.get("cwd")
        return SimpleNamespace(returncode=0, stdout='{"state":"healthy"}', stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    state = adapter.check("bd-test")

    assert state is not None
    assert state.state == "healthy"
    assert captured["cwd"] == str(tmp_path / "bd")

    print("✓ RunnerAdapter invokes dx-runner from canonical Beads cwd")


def test_runner_adapter_extracts_review_verdict_from_log(tmp_path):
    """Review chaining should work even if dx-runner report lacks a verdict field."""
    adapter = RunnerAdapter(provider="opencode")
    log_dir = Path("/tmp/dx-runner/opencode")
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "bd-test-review.log"
    log_path.write_text("noise\nREVISION_REQUIRED: fix the helper contract\n")

    try:
        verdict = adapter.extract_review_verdict("bd-test-review")
    finally:
        log_path.unlink(missing_ok=True)

    assert verdict == "REVISION_REQUIRED: fix the helper contract"

    print("✓ RunnerAdapter extracts review verdicts from logs")


def test_runner_adapter_extracts_markdown_wrapped_review_verdict(tmp_path):
    """Review verdict extraction should tolerate markdown-wrapped verdict lines."""
    adapter = RunnerAdapter(provider="opencode")
    log_dir = Path("/tmp/dx-runner/opencode")
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "bd-test-review.log"
    log_path.write_text(
        "## Review Findings\n\n"
        "`REVISION_REQUIRED`: tighten the fixture coverage claim\n"
    )

    try:
        verdict = adapter.extract_review_verdict("bd-test-review")
    finally:
        log_path.unlink(missing_ok=True)

    assert verdict == "REVISION_REQUIRED: tighten the fixture coverage claim"

    print("✓ RunnerAdapter extracts markdown-wrapped review verdicts")


def test_start_implement_marks_kickoff_env_blocked(tmp_path):
    """Failed starts before any run exists should not leave the wave healthy."""
    wave_id = "wave-start-failure"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Dispatchable task",
            dependencies=[],
        )
    }
    worktree = tmp_path / "agents" / "bd-test" / "prime-radiant-ai"
    worktree.mkdir(parents=True)
    loop.beads_manager.tasks["bd-test"].repo = "prime-radiant-ai"
    loop._ensure_worktree = lambda beads_id: worktree

    failure = RunnerStartResult(
        ok=False,
        returncode=2,
        reason_code="dx_runner_shell_preflight_failed",
        detail="dx-runner requires bash >= 4",
        command=["/Users/fengning/bin/dx-runner", "start"],
    )
    loop.runner_adapter.start = lambda *args, **kwargs: failure

    assert loop._start_implement("bd-test") is False
    assert loop.wave_status["state"] == "kickoff_env_blocked"
    assert loop.wave_status["blocker_code"] == "kickoff_env_blocked"
    assert (
        loop.wave_status["blocked_details"][0]["reason_code"]
        == "dx_runner_shell_preflight_failed"
    )

    print("✓ Failed starts produce truthful kickoff-env-blocked state")


def test_run_loop_persists_truthful_state_when_initial_dispatch_fails(tmp_path):
    """A failed initial dispatch should persist blocked state instead of healthy progress."""
    wave_id = "wave-dispatch-failure"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Dispatchable task",
            dependencies=[],
        )
    }
    loop.beads_manager.layers = [["bd-test"]]
    worktree = tmp_path / "agents" / "bd-test" / "prime-radiant-ai"
    worktree.mkdir(parents=True)
    loop.beads_manager.tasks["bd-test"].repo = "prime-radiant-ai"
    loop._ensure_worktree = lambda beads_id: worktree

    failure = RunnerStartResult(
        ok=False,
        returncode=21,
        reason_code="dx_runner_preflight_failed",
        detail="canonical model unavailable",
        command=["/opt/homebrew/bin/bash", "/Users/fengning/bin/dx-runner", "start"],
    )
    loop.runner_adapter.start = lambda *args, **kwargs: failure

    assert loop.run_loop(max_iterations=1) is False

    state = json.loads(loop.state_file.read_text())
    assert state["scheduler_state"]["dispatch_count"] == 0
    assert state["wave_status"]["state"] == "kickoff_env_blocked"
    assert state["wave_status"]["blocker_code"] == "kickoff_env_blocked"
    assert (
        state["wave_status"]["blocked_details"][0]["reason_code"]
        == "dx_runner_preflight_failed"
    )
    assert "exiting without resident loop" in state["wave_status"]["reason"]

    print("✓ Failed initial dispatch persists blocked state")


def test_run_loop_allows_dispatch_for_terminal_deps_without_pr_artifacts(
    tmp_path, monkeypatch
):
    """Bug C fix: deps with terminal status in cache should not block on missing PR artifacts."""
    wave_id = "wave-dispatch-terminal-dep"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-iey6": BeadsTask(
            beads_id="bd-iey6",
            title="Upstream done without artifact cache",
            repo="affordabot",
            dependencies=[],
            status="closed",
            details_loaded=True,
        ),
        "bd-hfk0": BeadsTask(
            beads_id="bd-hfk0",
            title="Downstream task",
            repo="affordabot",
            dependencies=["bd-iey6"],
            status="open",
            details_loaded=True,
        ),
    }
    loop.beads_manager.layers = [["bd-hfk0"]]
    loop.beads_manager.completed = {"bd-iey6"}
    loop.beads_manager.dependency_status_cache["bd-iey6"] = "closed"
    loop.beads_manager.dependency_metadata_cache["bd-iey6"] = {
        "title": "Closed upstream",
        "repo": "",
        "status": "closed",
        "close_reason": "",
    }

    monkeypatch.setattr(
        loop.implement_runner,
        "start",
        lambda **kwargs: MagicMock(state="exited_err", reason_code="test_inject"),
    )
    monkeypatch.setattr(
        loop.implement_runner, "check", lambda beads_id: MagicMock(state="missing")
    )

    dep_block = loop._check_dependency_artifacts("bd-hfk0")
    assert dep_block is None, "Terminal-status deps should not block dispatch"

    print("✓ terminal-status deps allow dispatch without PR artifacts")


def test_recover_closed_dependency_artifact_uses_default_repo_when_repo_missing(
    tmp_path, monkeypatch
):
    """Artifact recovery should use default repo when cached closed dependency repo is missing."""
    wave_id = "wave-recover-default-repo"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0, "default_repo": "affordabot"})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-hfk0": BeadsTask(
            beads_id="bd-hfk0",
            title="Downstream task",
            repo="affordabot",
            dependencies=["bd-iey6"],
        )
    }
    loop.beads_manager.completed = {"bd-iey6"}
    loop.beads_manager.dependency_status_cache["bd-iey6"] = "closed"
    loop.beads_manager.dependency_metadata_cache["bd-iey6"] = {
        "title": "Closed upstream",
        "repo": "",
        "status": "closed",
        "close_reason": "Completed via PR #362",
    }

    def fake_run(cmd, capture_output=None, text=None, timeout=None):
        assert cmd[:4] == ["gh", "pr", "view", "362"]
        assert "--repo" in cmd
        repo_idx = cmd.index("--repo")
        assert cmd[repo_idx + 1] == "stars-end/affordabot"
        return subprocess.CompletedProcess(
            cmd,
            0,
            stdout=json.dumps(
                {
                    "url": "https://github.com/stars-end/affordabot/pull/362",
                    "headRefOid": "a" * 40,
                }
            ),
            stderr="",
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    block = loop._check_dependency_artifacts("bd-hfk0")

    assert block is None
    assert loop.pr_enforcer.has_valid_artifact("bd-iey6")

    print("✓ closed dependency artifact recovery falls back to default repo")


def test_ensure_worktree_creates_missing_repo_workspace(tmp_path, monkeypatch):
    """dx-loop should provision the inferred repo worktree before dispatch."""
    wave_id = "wave-worktree-create"
    loop = DxLoop(
        wave_id,
        config={"cadence_seconds": 0, "worktree_base": str(tmp_path / "agents")},
    )
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-test": BeadsTask(
            beads_id="bd-test",
            title="Prime Radiant: fix auth lane",
            repo="prime-radiant-ai",
            dependencies=[],
        )
    }
    created = tmp_path / "agents" / "bd-test" / "prime-radiant-ai"

    def fake_run(cmd, **kwargs):
        created.mkdir(parents=True, exist_ok=True)
        return SimpleNamespace(returncode=0, stdout=f"{created}\n", stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    resolved = loop._ensure_worktree("bd-test")

    assert resolved == created
    assert created.is_dir()
    assert loop._get_worktree_path("bd-test") == created

    print("✓ Missing worktrees are provisioned for the inferred repo")


# ---------------------------------------------------------------------------
# v1.2 regression tests — bd-5w5o.28 hardening batch
# ---------------------------------------------------------------------------


def test_config_file_override_is_honored(tmp_path):
    """--config should merge YAML overrides into DEFAULT_CONFIG (bd-5w5o.27)."""
    config_path = tmp_path / "override.yaml"
    config_path.write_text("provider: cc-glm\ncadence_seconds: 120\nmax_attempts: 5\n")

    dx_loop_main = importlib.util.spec_from_file_location(
        "dx_loop_main_v12", REPO_ROOT / "scripts" / "dx_loop.py"
    )
    mod = importlib.util.module_from_spec(dx_loop_main)
    assert dx_loop_main.loader is not None
    dx_loop_main.loader.exec_module(mod)

    config = mod.load_config_file(str(config_path))

    assert config["provider"] == "cc-glm"
    assert config["cadence_seconds"] == 120
    assert config["max_attempts"] == 5
    assert config["max_revisions"] == 3  # unchanged default

    print("✓ --config file overrides are honored")


def test_config_missing_file_returns_defaults():
    """A nonexistent --config path should warn and return defaults."""
    dx_loop_main = importlib.util.spec_from_file_location(
        "dx_loop_main_missing", REPO_ROOT / "scripts" / "dx_loop.py"
    )
    mod = importlib.util.module_from_spec(dx_loop_main)
    assert dx_loop_main.loader is not None
    dx_loop_main.loader.exec_module(mod)

    config = mod.load_config_file("/nonexistent/path.yaml")
    assert config["provider"] == "opencode"

    print("✓ Missing config file returns defaults with warning")


def test_cmd_start_loads_config(tmp_path, capsys, monkeypatch):
    """cmd_start should create DxLoop with merged config when --config is given."""
    config_path = tmp_path / "test-config.yaml"
    config_path.write_text("cadence_seconds: 42\n")

    dx_loop_main = importlib.util.spec_from_file_location(
        "dx_loop_main_cmd", REPO_ROOT / "scripts" / "dx_loop.py"
    )
    mod = importlib.util.module_from_spec(dx_loop_main)
    assert dx_loop_main.loader is not None
    dx_loop_main.loader.exec_module(mod)

    args = SimpleNamespace(
        epic="bd-test-epic",
        wave_id="wave-config-test",
        config=str(config_path),
    )

    created_loop = {}

    class FakeDxLoop:
        def __init__(self, wave_id, config=None):
            self.wave_id = wave_id
            self.config = config or {}
            self.state_file = tmp_path / "loop_state.json"
            created_loop["instance"] = self

        def bootstrap_epic(self, epic_id):
            return True

        def _load_state(self):
            return False

        def adopt_running_jobs(self):
            return []

        def _save_state(self):
            pass

        def run_loop(self, max_iterations=100):
            return True

    monkeypatch.setattr(mod, "DxLoop", FakeDxLoop)
    rc = mod.cmd_start(args)

    assert rc == 0
    assert created_loop["instance"].config["cadence_seconds"] == 42
    assert created_loop["instance"].config["provider"] == "opencode"

    print("✓ cmd_start passes merged config to DxLoop")


def test_cmd_start_restart_skips_bootstrap_when_state_exists(tmp_path, monkeypatch):
    """Restarting the same wave_id should load state before bootstrap writes fresh state."""
    dx_loop_main = importlib.util.spec_from_file_location(
        "dx_loop_main_restart", REPO_ROOT / "scripts" / "dx_loop.py"
    )
    mod = importlib.util.module_from_spec(dx_loop_main)
    assert dx_loop_main.loader is not None
    dx_loop_main.loader.exec_module(mod)

    args = SimpleNamespace(
        epic="bd-test-epic",
        wave_id="wave-restart-test",
        config=None,
    )

    events = []

    class FakeDxLoop:
        def __init__(self, wave_id, config=None):
            self.wave_id = wave_id
            self.config = config or {}
            self.state_file = tmp_path / "loop_state.json"
            self.beads_manager = SimpleNamespace(tasks={"bd-live": object()})

        def bootstrap_epic(self, epic_id):
            events.append(("bootstrap", epic_id))
            return True

        def _load_state(self):
            events.append(("load", self.wave_id))
            return True

        def adopt_running_jobs(self):
            events.append(("adopt", self.wave_id))
            return ["bd-live"]

        def _save_state(self):
            events.append(("save", self.wave_id))

        def run_loop(self, max_iterations=100):
            events.append(("run", max_iterations))
            return True

    monkeypatch.setattr(mod, "DxLoop", FakeDxLoop)

    rc = mod.cmd_start(args)

    assert rc == 0
    assert ("bootstrap", "bd-test-epic") not in events
    assert events[:2] == [("load", "wave-restart-test"), ("adopt", "wave-restart-test")]

    print("✓ cmd_start restart loads persisted state before bootstrap")


def test_cmd_start_restart_bootstraps_when_state_missing_task_graph(
    tmp_path, monkeypatch
):
    """Restart should rebuild from Beads if persisted state lacks the task graph."""
    dx_loop_main = importlib.util.spec_from_file_location(
        "dx_loop_main_restart_empty", REPO_ROOT / "scripts" / "dx_loop.py"
    )
    mod = importlib.util.module_from_spec(dx_loop_main)
    assert dx_loop_main.loader is not None
    dx_loop_main.loader.exec_module(mod)

    args = SimpleNamespace(
        epic="bd-test-epic",
        wave_id="wave-restart-empty",
        config=None,
    )

    events = []

    class FakeDxLoop:
        def __init__(self, wave_id, config=None):
            self.wave_id = wave_id
            self.config = config or {}
            self.state_file = tmp_path / "loop_state.json"
            self.beads_manager = SimpleNamespace(tasks={})

        def bootstrap_epic(self, epic_id):
            events.append(("bootstrap", epic_id))
            self.beads_manager.tasks = {"bd-live": object()}
            return True

        def _load_state(self):
            events.append(("load", self.wave_id))
            return True

        def adopt_running_jobs(self):
            events.append(("adopt", self.wave_id))
            return []

        def _save_state(self):
            events.append(("save", self.wave_id))

        def run_loop(self, max_iterations=100):
            events.append(("run", max_iterations))
            return True

    monkeypatch.setattr(mod, "DxLoop", FakeDxLoop)

    rc = mod.cmd_start(args)

    assert rc == 0
    assert ("bootstrap", "bd-test-epic") in events
    assert events[0] == ("load", "wave-restart-empty")

    print("✓ cmd_start can rebuild restart state when task graph is missing")


def test_cmd_start_fresh_persists_state_before_bootstrap(tmp_path, monkeypatch):
    """Fresh starts should materialize a wave record before bootstrap work begins."""
    dx_loop_main = importlib.util.spec_from_file_location(
        "dx_loop_main_fresh_bootstrap", REPO_ROOT / "scripts" / "dx_loop.py"
    )
    mod = importlib.util.module_from_spec(dx_loop_main)
    assert dx_loop_main.loader is not None
    dx_loop_main.loader.exec_module(mod)

    args = SimpleNamespace(
        epic="bd-test-epic",
        wave_id="wave-fresh-bootstrap",
        config=None,
    )

    events = []

    class FakeDxLoop:
        def __init__(self, wave_id, config=None):
            self.wave_id = wave_id
            self.config = config or {}
            self.state_file = tmp_path / "loop_state.json"
            self.beads_manager = SimpleNamespace(tasks={})

        def bootstrap_epic(self, epic_id):
            events.append(("bootstrap", epic_id, self.state_file.exists()))
            self.beads_manager.tasks = {"bd-live": object()}
            return True

        def _load_state(self):
            events.append(("load", self.wave_id))
            return False

        def adopt_running_jobs(self):
            events.append(("adopt", self.wave_id))
            return []

        def _save_state(self):
            events.append(("save", self.wave_id))
            self.state_file.write_text("{}")

        def run_loop(self, max_iterations=100):
            events.append(("run", max_iterations))
            return True

    monkeypatch.setattr(mod, "DxLoop", FakeDxLoop)

    rc = mod.cmd_start(args)

    assert rc == 0
    assert events[0] == ("load", "wave-fresh-bootstrap")
    assert events[1] == ("save", "wave-fresh-bootstrap")
    assert events[2] == ("bootstrap", "bd-test-epic", True)

    print("✓ Fresh start persists wave state before bootstrap")


def test_bootstrap_state_persisted_before_run_loop(tmp_path, monkeypatch):
    """Bootstrap state should be saved to disk before run_loop starts (bd-5w5o.19)."""
    wave_id = "wave-bootstrap-vis"
    state_file = tmp_path / "waves" / wave_id / "loop_state.json"
    config = {"cadence_seconds": 0}

    saved_states = []

    class FakeDxLoop:
        def __init__(self, wid, config=None):
            self.wave_id = wid
            self.config = config or {}
            self.state_file = state_file
            self.wave_dir = tmp_path / "waves" / wid

        def bootstrap_epic(self, epic_id):
            self.tasks_loaded = True
            return True

        def _load_state(self):
            return False

        def adopt_running_jobs(self):
            return []

        def _save_state(self):
            saved_states.append(True)
            self.wave_dir.mkdir(parents=True, exist_ok=True)
            state_file.write_text(
                json.dumps(
                    {"wave_id": self.wave_id, "wave_status": {"state": "pending"}}
                )
            )

        def run_loop(self, max_iterations=100):
            return True

    dx_loop_main = importlib.util.spec_from_file_location(
        "dx_loop_main_bs", REPO_ROOT / "scripts" / "dx_loop.py"
    )
    mod = importlib.util.module_from_spec(dx_loop_main)
    assert dx_loop_main.loader is not None
    dx_loop_main.loader.exec_module(mod)

    monkeypatch.setattr(mod, "DxLoop", FakeDxLoop)

    args = SimpleNamespace(epic="bd-test", wave_id=wave_id, config=None)
    mod.cmd_start(args)

    assert len(saved_states) >= 1, "State should be saved before run_loop"
    assert state_file.exists(), "State file should exist immediately after bootstrap"

    print("✓ Bootstrap state is persisted before run_loop starts")


def test_cmd_start_fresh_adopts_running_jobs(tmp_path, monkeypatch):
    """Fresh starts should adopt live jobs after bootstrap, not only restart flows."""
    dx_loop_main = importlib.util.spec_from_file_location(
        "dx_loop_main_fresh_adopt", REPO_ROOT / "scripts" / "dx_loop.py"
    )
    mod = importlib.util.module_from_spec(dx_loop_main)
    assert dx_loop_main.loader is not None
    dx_loop_main.loader.exec_module(mod)

    args = SimpleNamespace(
        epic="bd-test-epic",
        wave_id="wave-fresh-adopt",
        config=None,
    )

    events = []

    class FakeDxLoop:
        def __init__(self, wave_id, config=None):
            self.wave_id = wave_id
            self.config = config or {}
            self.state_file = tmp_path / "loop_state.json"
            self.beads_manager = SimpleNamespace(tasks={})

        def bootstrap_epic(self, epic_id):
            events.append(("bootstrap", epic_id))
            self.beads_manager.tasks = {"bd-live": object()}
            return True

        def _load_state(self):
            events.append(("load", self.wave_id))
            return False

        def adopt_running_jobs(self):
            events.append(("adopt", self.wave_id))
            return ["bd-live"]

        def _save_state(self):
            events.append(("save", self.wave_id))

        def run_loop(self, max_iterations=100):
            events.append(("run", max_iterations))
            return True

    monkeypatch.setattr(mod, "DxLoop", FakeDxLoop)

    rc = mod.cmd_start(args)

    assert rc == 0
    assert ("adopt", "wave-fresh-adopt") in events
    assert events.index(("adopt", "wave-fresh-adopt")) > events.index(
        ("bootstrap", "bd-test-epic")
    )

    print("✓ Fresh start adopts already-running jobs after bootstrap")


def test_adopt_running_jobs_marks_active_in_scheduler(tmp_path):
    """Restart should adopt already-running dx-runner jobs (bd-5w5o.25)."""
    wave_id = "wave-adoption-test"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-active": BeadsTask(
            beads_id="bd-active",
            title="Active task",
            dependencies=[],
        ),
        "bd-idle": BeadsTask(
            beads_id="bd-idle",
            title="Idle task",
            dependencies=[],
        ),
    }

    call_log = []

    def fake_check(beads_id):
        call_log.append(beads_id)
        if beads_id == "bd-active":
            return RunnerTaskState(
                beads_id=beads_id,
                state="healthy",
                reason_code="recent_log_activity",
            )
        return RunnerTaskState(beads_id=beads_id, state="missing")

    loop.runner_adapter.check = fake_check

    adopted = loop.adopt_running_jobs()

    assert "bd-active" in adopted
    assert "bd-idle" not in adopted
    assert loop.scheduler.state.is_active("bd-active")
    assert not loop.scheduler.state.is_active("bd-idle")

    baton = loop.baton_manager.get_state("bd-active")
    assert baton is not None
    assert baton.phase == BatonPhase.IMPLEMENT

    print("✓ Already-running jobs are adopted on restart with baton state")


def test_adopt_running_jobs_rebuilds_baton_for_fresh_restart(tmp_path):
    """Adoption on fresh restart should set baton to IMPLEMENT (bd-5w5o.25 P0)."""
    wave_id = "wave-adoption-fresh"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-live": BeadsTask(
            beads_id="bd-live",
            title="Live task",
            dependencies=[],
        ),
    }

    assert loop.baton_manager.get_state("bd-live") is None

    loop.runner_adapter.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="healthy",
        reason_code="recent_log_activity",
    )

    adopted = loop.adopt_running_jobs()

    assert "bd-live" in adopted
    baton = loop.baton_manager.get_state("bd-live")
    assert baton is not None
    assert baton.phase == BatonPhase.IMPLEMENT
    assert baton.implement_run_id is not None
    assert loop.scheduler.state.is_active("bd-live", "implement")

    print("✓ Fresh restart adoption rebuilds baton state for implement phase")


def test_adopt_running_jobs_keys_by_base_beads_id(tmp_path):
    """Adoption should use base beads_id, not bd-*-review (bd-5w5o.25 P0)."""
    wave_id = "wave-adoption-key"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-reviewing": BeadsTask(
            beads_id="bd-reviewing",
            title="Reviewing task",
            dependencies=[],
        ),
    }
    loop.baton_manager.start_implement("bd-reviewing")
    loop.baton_manager.complete_implement(
        "bd-reviewing", pr_url="http://example/1", pr_head_sha="a" * 40
    )
    loop.baton_manager.start_review("bd-reviewing", run_id="review-run-1")

    loop.review_runner.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="healthy",
        reason_code="recent_log_activity",
    )
    loop.implement_runner.check = lambda beads_id: None

    adopted = loop.adopt_running_jobs()

    assert "bd-reviewing" in adopted
    assert loop.scheduler.state.is_active("bd-reviewing", "review")
    assert not any(
        "bd-reviewing-review" in key for key in loop.scheduler.state.active_beads_ids
    )

    print("✓ Adoption keys by base beads_id, not bd-*-review")


def test_adopt_running_jobs_skips_completed(tmp_path):
    """Adoption should skip tasks already marked completed."""
    wave_id = "wave-adoption-skip"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-done": BeadsTask(
            beads_id="bd-done",
            title="Completed task",
            dependencies=[],
        ),
    }
    loop.scheduler.state.mark_completed("bd-done")

    def fake_check(beads_id):
        return RunnerTaskState(beads_id=beads_id, state="healthy")

    loop.runner_adapter.check = fake_check

    adopted = loop.adopt_running_jobs()

    assert adopted == []
    assert not loop.scheduler.state.is_active("bd-done")

    print("✓ Adoption skips completed tasks")


def test_monitor_no_rc_file_classified_as_kickoff_defect(tmp_path):
    """monitor_no_rc_file should be kickoff_env_blocked, not retryable (bd-5w5o.22+bd-5w5o.26)."""
    wave_id = "wave-rc-defect"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-rc-fail": BeadsTask(
            beads_id="bd-rc-fail",
            title="RC defect task",
            dependencies=[],
        )
    }

    loop.baton_manager.start_implement("bd-rc-fail", run_id="run-1")
    loop.scheduler.state.mark_dispatched("bd-rc-fail", "implement")
    loop.runner_adapter.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="exited_err",
        reason_code="monitor_no_rc_file",
    )
    loop.runner_adapter.extract_agent_output = lambda beads_id: ""
    loop.runner_adapter.extract_pr_artifacts = lambda beads_id: None

    loop._check_implement_progress("bd-rc-fail")

    assert loop.wave_status["state"] == "kickoff_env_blocked"
    assert loop.wave_status["blocker_code"] == "kickoff_env_blocked"
    assert "lifecycle defect" in loop.wave_status["reason"]
    assert loop.scheduler.state.is_blocked("bd-rc-fail")

    detail = loop.wave_status["blocked_details"][0]
    assert detail["reason_code"] == "monitor_no_rc_file"
    assert "rc file" in detail["detail"]

    baton = loop.baton_manager.get_state("bd-rc-fail")
    assert baton is not None
    assert baton.attempt == 1, "monitor_no_rc_file should NOT increment retry count"

    print("✓ monitor_no_rc_file classified as kickoff_env_blocked lifecycle defect")


def test_late_finalize_no_rc_also_classified_as_kickoff_defect(tmp_path):
    """late_finalize_no_rc should be treated the same as monitor_no_rc_file."""
    wave_id = "wave-late-finalize"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-late": BeadsTask(
            beads_id="bd-late",
            title="Late finalize task",
            dependencies=[],
        )
    }

    loop.baton_manager.start_implement("bd-late", run_id="run-1")
    loop.scheduler.state.mark_dispatched("bd-late", "implement")
    loop.runner_adapter.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="exited_err",
        reason_code="late_finalize_no_rc",
    )
    loop.runner_adapter.extract_agent_output = lambda beads_id: ""
    loop.runner_adapter.extract_pr_artifacts = lambda beads_id: None

    loop._check_implement_progress("bd-late")

    assert loop.wave_status["state"] == "kickoff_env_blocked"
    assert loop.wave_status["blocker_code"] == "kickoff_env_blocked"

    print("✓ late_finalize_no_rc also classified as kickoff_env_blocked defect")


def test_normal_retryable_failure_still_enters_redispatch(tmp_path):
    """Non-lifecycle-defect failures should still enter deterministic_redispatch_needed."""
    wave_id = "wave-normal-retry"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-retry": BeadsTask(
            beads_id="bd-retry",
            title="Retry task",
            dependencies=[],
        )
    }

    loop.baton_manager.start_implement("bd-retry", run_id="run-1")
    loop.scheduler.state.mark_dispatched("bd-retry", "implement")
    loop.runner_adapter.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="exited_err",
        reason_code="stalled_no_progress",
    )
    loop.runner_adapter.extract_agent_output = lambda beads_id: ""
    loop.runner_adapter.extract_pr_artifacts = lambda beads_id: None

    loop._check_implement_progress("bd-retry")

    assert loop.wave_status["state"] == "deterministic_redispatch_needed"
    assert loop.wave_status["blocker_code"] == "deterministic_redispatch_needed"

    print("✓ Normal retryable failures still enter redispatch state")


def test_terminal_provider_failure_updates_wave_status_to_run_blocked(tmp_path):
    """Terminal provider failures should not leave the wave falsely healthy."""
    wave_id = "wave-provider-blocked"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-provider-blocked": BeadsTask(
            beads_id="bd-provider-blocked",
            title="Provider blocked task",
            dependencies=[],
        )
    }

    loop.baton_manager.start_implement("bd-provider-blocked", run_id="run-1")
    loop.scheduler.state.mark_dispatched("bd-provider-blocked", "implement")
    loop.wave_status = {
        "state": "in_progress_healthy",
        "blocker_code": None,
        "reason": "All ready tasks already active, waiting for progress",
        "blocked_details": [],
        "dispatchable_tasks": ["bd-provider-blocked"],
    }
    loop.implement_runner.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="stopped",
        reason_code="opencode_rate_limited",
    )
    loop.implement_runner.extract_agent_output = lambda beads_id: ""
    loop.implement_runner.extract_pr_artifacts = lambda beads_id: None

    loop._check_implement_progress("bd-provider-blocked")

    assert loop.wave_status["state"] == "run_blocked"
    assert loop.wave_status["blocker_code"] == "run_blocked"
    assert loop.scheduler.state.is_blocked("bd-provider-blocked")
    assert not loop.scheduler.state.is_active("bd-provider-blocked", "implement")

    print("✓ Terminal provider failures now update wave status to run_blocked")


def test_adopt_and_no_double_dispatch(tmp_path):
    """After adoption, run_loop should not double-dispatch adopted tasks."""
    wave_id = "wave-adopt-no-double"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-adopted": BeadsTask(
            beads_id="bd-adopted",
            title="Adopted task",
            dependencies=[],
        )
    }
    loop.beads_manager.layers = [["bd-adopted"]]

    loop.runner_adapter.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="healthy",
        reason_code="recent_log_activity",
    )
    adopted = loop.adopt_running_jobs()

    assert loop.scheduler.state.is_active("bd-adopted")
    dispatchable = []
    for tid in loop.beads_manager.layers[0]:
        if not loop.scheduler.state.is_active(
            tid
        ) and not loop.scheduler.state.is_completed(tid):
            dispatchable.append(tid)

    assert dispatchable == [], "Adopted task should not appear in dispatchable list"

    print("✓ Adopted tasks are not double-dispatched")


def test_adopt_does_not_adopt_exited_jobs(tmp_path):
    """Adoption should only adopt RUNNING jobs, not exited ones (P1)."""
    wave_id = "wave-adopt-exited"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-exited": BeadsTask(
            beads_id="bd-exited",
            title="Exited task",
            dependencies=[],
        ),
    }

    loop.runner_adapter.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="exited_ok",
        reason_code="process_exit_with_rc",
    )

    adopted = loop.adopt_running_jobs()

    assert adopted == []
    assert not loop.scheduler.state.is_active("bd-exited")
    assert loop.baton_manager.get_state("bd-exited") is None

    print("✓ Exited jobs are not adopted")


def test_dispatch_fanout_capped_at_max_parallel(tmp_path, capsys):
    """Dispatch should not exceed max_parallel even when more tasks are ready."""
    wave_id = "wave-fanout-cap"
    loop = DxLoop(
        wave_id,
        config={"cadence_seconds": 0, "max_parallel": 2},
    )
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        f"bd-task-{i}": BeadsTask(
            beads_id=f"bd-task-{i}",
            title=f"Task {i}",
            dependencies=[],
        )
        for i in range(5)
    }
    loop.beads_manager.layers = [[f"bd-task-{i}" for i in range(5)]]

    worktree = tmp_path / "agents" / "bd-task-0" / "agent-skills"
    worktree.mkdir(parents=True)
    for i in range(5):
        loop.beads_manager.tasks[f"bd-task-{i}"].repo = "agent-skills"

    dispatch_count = 0

    def fake_start(*args, **kwargs):
        nonlocal dispatch_count
        dispatch_count += 1
        return RunnerStartResult(
            ok=True,
            returncode=0,
            stdout="started",
            command=["dx-runner", "start"],
        )

    loop._ensure_worktree = lambda beads_id: worktree
    loop.implement_runner.start = fake_start
    loop.review_runner.start = fake_start

    loop.run_loop(max_iterations=1)

    assert dispatch_count == 2, (
        f"Expected 2 dispatches (max_parallel=2), got {dispatch_count}"
    )
    assert loop.scheduler.state.dispatch_count == 2

    print("✓ Dispatch fanout capped at max_parallel")


def test_capacity_blocked_stops_dispatch_in_same_cycle(tmp_path, capsys):
    """A provider-capacity block should stop further dispatch attempts in the cycle."""
    wave_id = "wave-capacity-stop"
    loop = DxLoop(
        wave_id,
        config={"cadence_seconds": 0, "max_parallel": 3},
    )
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        f"bd-task-{i}": BeadsTask(
            beads_id=f"bd-task-{i}",
            title=f"Task {i}",
            dependencies=[],
        )
        for i in range(3)
    }
    loop.beads_manager.layers = [[f"bd-task-{i}" for i in range(3)]]

    worktree = tmp_path / "agents" / "bd-task-0" / "agent-skills"
    worktree.mkdir(parents=True)
    for i in range(3):
        loop.beads_manager.tasks[f"bd-task-{i}"].repo = "agent-skills"

    dispatch_order = []

    def fake_start(*args, **kwargs):
        dispatch_order.append("attempted")
        return RunnerStartResult(
            ok=False,
            returncode=26,
            reason_code="dx_runner_provider_capacity_blocked",
            detail="opencode concurrency cap exceeded (2/2)",
            command=["dx-runner", "start"],
        )

    loop._ensure_worktree = lambda beads_id: worktree
    loop.implement_runner.start = fake_start
    loop.review_runner.start = fake_start

    loop.run_loop(max_iterations=1)

    assert len(dispatch_order) == 1, (
        f"Expected 1 dispatch attempt (stopped after capacity block), got {len(dispatch_order)}"
    )
    assert loop.wave_status["state"] == "run_blocked"
    assert loop.wave_status["blocker_code"] == "run_blocked"
    assert "Provider at capacity" in loop.wave_status["reason"]

    captured = capsys.readouterr()
    assert "Provider at capacity, stopping dispatch" in captured.err

    print("✓ Capacity block stops dispatch in same cycle")


def test_no_false_healthy_state_during_capacity_block(tmp_path):
    """Wave status must not claim healthy when all dispatches hit capacity."""
    wave_id = "wave-no-fake-healthy"
    loop = DxLoop(
        wave_id,
        config={"cadence_seconds": 0, "max_parallel": 2},
    )
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-a": BeadsTask(
            beads_id="bd-a",
            title="Task A",
            dependencies=[],
        ),
        "bd-b": BeadsTask(
            beads_id="bd-b",
            title="Task B",
            dependencies=[],
        ),
    }
    loop.beads_manager.layers = [["bd-a", "bd-b"]]

    worktree = tmp_path / "agents" / "bd-a" / "agent-skills"
    worktree.mkdir(parents=True)
    loop.beads_manager.tasks["bd-a"].repo = "agent-skills"
    loop.beads_manager.tasks["bd-b"].repo = "agent-skills"

    first_call = {"done": False}

    def fake_start(*args, **kwargs):
        if not first_call["done"]:
            first_call["done"] = True
            return RunnerStartResult(
                ok=False,
                returncode=26,
                reason_code="dx_runner_provider_capacity_blocked",
                detail="opencode concurrency cap exceeded (2/2)",
                command=["dx-runner", "start"],
            )
        return RunnerStartResult(
            ok=True,
            returncode=0,
            stdout="started",
            command=["dx-runner", "start"],
        )

    loop._ensure_worktree = lambda beads_id: worktree
    loop.implement_runner.start = fake_start
    loop.review_runner.start = fake_start

    loop.run_loop(max_iterations=1)

    state = json.loads(loop.state_file.read_text())
    assert state["wave_status"]["state"] != "in_progress_healthy", (
        "Wave must not claim healthy when dispatch hit capacity block"
    )
    assert state["wave_status"]["state"] in ("run_blocked", "kickoff_env_blocked")

    print("✓ No false healthy state during capacity block")


def test_completed_wave_restart_preserves_status(tmp_path):
    """Restarting a completed wave must not regress to in_progress_healthy (bd-5w5o.40.1)."""
    wave_id = "wave-completed-restart"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-done-1": BeadsTask(
            beads_id="bd-done-1",
            title="Completed task 1",
            dependencies=[],
        ),
        "bd-done-2": BeadsTask(
            beads_id="bd-done-2",
            title="Completed task 2",
            dependencies=["bd-done-1"],
        ),
    }
    loop.beads_manager.layers = [["bd-done-1"], ["bd-done-2"]]
    loop.beads_manager.completed = {"bd-done-1", "bd-done-2"}
    loop.scheduler.state.mark_completed("bd-done-1")
    loop.scheduler.state.mark_completed("bd-done-2")
    loop.baton_manager.baton_states["bd-done-1"] = BatonState(
        beads_id="bd-done-1",
        phase=BatonPhase.COMPLETE,
        implement_run_id="run-1",
        pr_url="https://github.com/test/repo/pull/1",
        pr_head_sha="a" * 40,
    )
    loop.baton_manager.baton_states["bd-done-2"] = BatonState(
        beads_id="bd-done-2",
        phase=BatonPhase.COMPLETE,
        implement_run_id="run-2",
        pr_url="https://github.com/test/repo/pull/2",
        pr_head_sha="b" * 40,
    )
    loop._set_wave_status(
        LoopState.COMPLETED,
        None,
        "Wave complete - no pending tasks",
    )
    loop._save_state()

    loop2 = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop2.wave_dir = tmp_path / "waves" / wave_id
    loop2.state_file = loop2.wave_dir / "loop_state.json"

    result = loop2.run_loop(max_iterations=1)

    assert result is True
    assert loop2.wave_status["state"] == "completed"
    assert not loop2.beads_manager.has_pending_tasks()

    state = json.loads(loop2.state_file.read_text())
    assert state["wave_status"]["state"] == "completed"

    print("✓ Completed wave restart preserves status without regression")


def test_completed_wave_restart_no_in_progress_healthy_regression(tmp_path):
    """Restart with partially completed state must not regress when checking progress."""
    wave_id = "wave-partial-completed-restart"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-task": BeadsTask(
            beads_id="bd-task",
            title="Single task",
            dependencies=[],
        ),
    }
    loop.beads_manager.layers = [["bd-task"]]
    loop.beads_manager.completed = {"bd-task"}
    loop.scheduler.state.mark_completed("bd-task")
    loop.baton_manager.baton_states["bd-task"] = BatonState(
        beads_id="bd-task",
        phase=BatonPhase.COMPLETE,
        implement_run_id="run-1",
        pr_url="https://github.com/test/repo/pull/1",
        pr_head_sha="a" * 40,
    )
    loop._set_wave_status(
        LoopState.COMPLETED,
        None,
        "Wave complete - no pending tasks",
    )
    loop._save_state()

    loop2 = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop2.wave_dir = tmp_path / "waves" / wave_id
    loop2.state_file = loop2.wave_dir / "loop_state.json"
    loop2.runner_adapter.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="exited_ok",
        reason_code="process_exit_with_rc",
    )

    result = loop2.run_loop(max_iterations=1)

    assert result is True
    assert loop2.wave_status["state"] == "completed", (
        f"Expected 'completed', got '{loop2.wave_status['state']}'"
    )

    print("✓ Completed wave restart does not regress to in_progress_healthy")


def test_runner_adapter_appends_model_flag():
    """RunnerAdapter.start() should append --model <id> when model is provided."""
    captured_args = []

    class FakeAdapter(RunnerAdapter):
        def _run_dx_runner(self, args, timeout=30):
            captured_args.extend(args)
            return RunnerStartResult(
                ok=True,
                returncode=0,
                command=["dx-runner"] + args,
            )

    adapter = FakeAdapter(provider="opencode", beads_repo_path="/tmp/bd")
    adapter.start("bd-test", Path("/tmp/prompt"), model="zai-coding-plan/glm-5")

    assert "--model" in captured_args
    idx = captured_args.index("--model")
    assert captured_args[idx + 1] == "zai-coding-plan/glm-5"


def test_runner_adapter_no_model_flag_when_null():
    """RunnerAdapter.start() should NOT append --model when model is None."""
    captured_args = []

    class FakeAdapter(RunnerAdapter):
        def _run_dx_runner(self, args, timeout=30):
            captured_args.extend(args)
            return RunnerStartResult(
                ok=True,
                returncode=0,
                command=["dx-runner"] + args,
            )

    adapter = FakeAdapter(provider="opencode", beads_repo_path="/tmp/bd")
    adapter.start("bd-test", Path("/tmp/prompt"), model=None)

    assert "--model" not in captured_args


def test_runner_adapter_review_model_propagation():
    """RunnerAdapter.start() should propagate review model to --model flag."""
    captured_args = []

    class FakeAdapter(RunnerAdapter):
        def _run_dx_runner(self, args, timeout=30):
            captured_args.extend(args)
            return RunnerStartResult(
                ok=True,
                returncode=0,
                command=["dx-runner"] + args,
            )

    adapter = FakeAdapter(provider="opencode", beads_repo_path="/tmp/bd")
    adapter.start(
        "bd-test-review", Path("/tmp/prompt"), model="zai-coding-plan/glm-5.1"
    )

    assert "--model" in captured_args
    idx = captured_args.index("--model")
    assert captured_args[idx + 1] == "zai-coding-plan/glm-5.1"


if __name__ == "__main__":
    test_no_duplicate_dispatch()
    test_notification_first_occurrence()
    test_state_persistence_round_trip()
    test_scheduler_state_persistence()
    test_restart_suppresses_unchanged_blocker_notifications()
    test_describe_wave_readiness_reports_dependency_blockers()
    test_dispatch_fanout_capped_at_max_parallel()
    test_capacity_blocked_stops_dispatch_in_same_cycle()
    test_no_false_healthy_state_during_capacity_block()
    test_completed_wave_restart_preserves_status()
    test_completed_wave_restart_no_in_progress_healthy_regression()
    test_runner_adapter_appends_model_flag()
    test_runner_adapter_no_model_flag_when_null()
    test_runner_adapter_review_model_propagation()
    print("\nAll v1.1 fix tests passed!")


# ---------------------------------------------------------------------------
# v1.4 truth-hardening tests — bd-xifc incident bundle
# ---------------------------------------------------------------------------


def test_external_close_detection_forces_baton_to_complete(tmp_path, monkeypatch):
    """An externally closed Beads task should force baton to COMPLETE."""
    wave_id = "wave-external-close-baton"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-closed-externally": BeadsTask(
            beads_id="bd-closed-externally",
            title="Externally closed task",
            repo="agent-skills",
            dependencies=[],
        )
    }
    loop.beads_manager.layers = [["bd-closed-externally"]]
    loop.baton_manager.start_implement("bd-closed-externally", run_id="run-1")
    loop.scheduler.state.mark_dispatched("bd-closed-externally", "implement")

    loop.implement_runner.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id, state="exited_ok"
    )

    def fake_run(cmd, **kwargs):
        beads_id = cmd[2]
        if beads_id == "bd-closed-externally":
            payload = [
                {
                    "id": beads_id,
                    "title": "Externally closed task",
                    "status": "closed",
                    "close_reason": "Merged manually",
                }
            ]
        else:
            raise AssertionError(f"unexpected bd show call for {beads_id}")
        return subprocess.CompletedProcess(
            cmd, 0, stdout=json.dumps(payload), stderr=""
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    loop._check_progress()

    baton = loop.baton_manager.get_state("bd-closed-externally")
    assert baton is not None
    assert baton.phase == BatonPhase.COMPLETE
    assert "bd-closed-externally" in loop.beads_manager.completed
    assert loop.scheduler.state.is_completed("bd-closed-externally")
    assert baton.metadata.get("external_close_status") == "closed"

    print("✓ Externally closed task forces baton to COMPLETE")


def test_external_close_clears_scheduler_activity(tmp_path, monkeypatch):
    """Externally closed tasks should be removed from active and blocked sets."""
    wave_id = "wave-external-close-scheduler"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-closed-review": BeadsTask(
            beads_id="bd-closed-review",
            title="Closed during review",
            repo="agent-skills",
            dependencies=[],
        )
    }
    loop.beads_manager.layers = [["bd-closed-review"]]
    loop.baton_manager.start_implement("bd-closed-review")
    loop.baton_manager.complete_implement(
        "bd-closed-review", pr_url="http://example/1", pr_head_sha="a" * 40
    )
    loop.baton_manager.start_review("bd-closed-review", run_id="review-run-1")
    loop.scheduler.state.mark_dispatched("bd-closed-review", "review")

    loop.review_runner.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id, state="exited_ok"
    )

    def fake_run(cmd, **kwargs):
        beads_id = cmd[2]
        payload = [
            {
                "id": beads_id,
                "title": "Closed during review",
                "status": "resolved",
                "close_reason": "Superseded by PR #500",
            }
        ]
        return subprocess.CompletedProcess(
            cmd, 0, stdout=json.dumps(payload), stderr=""
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    loop._check_progress()

    assert not loop.scheduler.state.is_active("bd-closed-review")
    assert not loop.scheduler.state.is_blocked("bd-closed-review")
    assert loop.scheduler.state.is_completed("bd-closed-review")

    print("✓ Externally closed task clears all scheduler activity")


def test_wave_readiness_excludes_externally_closed_tasks(tmp_path, monkeypatch):
    """describe_wave_readiness should not list externally closed tasks as dispatchable."""
    manager = BeadsWaveManager()
    manager.tasks = {
        "bd-open": BeadsTask(
            beads_id="bd-open",
            title="Open task",
            dependencies=[],
            details_loaded=True,
        ),
        "bd-closed": BeadsTask(
            beads_id="bd-closed",
            title="Closed task",
            dependencies=[],
            details_loaded=True,
            status="open",
        ),
    }
    manager.layers = [["bd-open", "bd-closed"]]

    def fake_run(cmd, **kwargs):
        beads_id = cmd[2]
        if beads_id == "bd-closed":
            payload = [
                {
                    "id": beads_id,
                    "status": "closed",
                    "close_reason": "Done outside loop",
                }
            ]
        else:
            payload = [{"id": beads_id, "status": "open"}]
        return subprocess.CompletedProcess(
            cmd, 0, stdout=json.dumps(payload), stderr=""
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    manager.refresh_task_status("bd-closed")

    readiness = manager.describe_wave_readiness()

    assert "bd-closed" in manager.completed
    assert "bd-closed" not in readiness.ready
    assert "bd-closed" not in readiness.pending_tasks
    assert "bd-open" in readiness.ready

    print("✓ Externally closed tasks excluded from wave readiness")


def test_verdict_sidecar_preferred_over_transcript(tmp_path):
    """A structured verdict sidecar should be preferred over transcript parsing."""
    adapter = RunnerAdapter(provider="opencode")
    worktree = tmp_path / "agents" / "bd-sidecar-test" / "agent-skills"
    sidecar_dir = worktree / ".dx-loop"
    sidecar_dir.mkdir(parents=True)
    (sidecar_dir / "verdict.json").write_text(
        json.dumps({"verdict": "APPROVED", "detail": "All tests pass"})
    )

    verdict = adapter.extract_verdict_sidecar(worktree)

    assert verdict is not None
    assert "APPROVED" in verdict
    assert "All tests pass" in verdict

    print("✓ Structured verdict sidecar is preferred")


def test_verdict_fallback_to_transcript_when_no_sidecar(tmp_path):
    """Verdict extraction should fall back to transcript when no sidecar exists."""
    adapter = RunnerAdapter(provider="opencode")
    worktree = tmp_path / "agents" / "bd-no-sidecar" / "agent-skills"
    worktree.mkdir(parents=True)

    verdict = adapter.extract_verdict_sidecar(worktree)

    assert verdict is None

    log_dir = Path("/tmp/dx-runner/opencode")
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "bd-no-sidecar-review.log"
    log_path.write_text("Some text\nAPPROVED: looks good\n")

    try:
        transcript_verdict = adapter.extract_review_verdict("bd-no-sidecar-review")
    finally:
        log_path.unlink(missing_ok=True)

    assert transcript_verdict == "APPROVED: looks good"

    print("✓ Verdict falls back to transcript parsing when sidecar absent")


def test_verdict_sidecar_revision_required(tmp_path):
    """Sidecar should handle REVISION_REQUIRED verdicts."""
    adapter = RunnerAdapter(provider="opencode")
    worktree = tmp_path / "agents" / "bd-revision" / "agent-skills"
    sidecar_dir = worktree / ".dx-loop"
    sidecar_dir.mkdir(parents=True)
    (sidecar_dir / "verdict.json").write_text(
        json.dumps({"verdict": "REVISION_REQUIRED", "detail": "Missing test coverage"})
    )

    verdict = adapter.extract_verdict_sidecar(worktree)

    assert verdict is not None
    assert "REVISION_REQUIRED" in verdict
    assert "Missing test coverage" in verdict

    print("✓ Sidecar handles REVISION_REQUIRED verdicts")


def test_verdict_sidecar_blocked(tmp_path):
    """Sidecar should handle BLOCKED verdicts."""
    adapter = RunnerAdapter(provider="opencode")
    worktree = tmp_path / "agents" / "bd-blocked" / "agent-skills"
    sidecar_dir = worktree / ".dx-loop"
    sidecar_dir.mkdir(parents=True)
    (sidecar_dir / "verdict.json").write_text(
        json.dumps({"verdict": "BLOCKED", "detail": "Critical security issue"})
    )

    verdict = adapter.extract_verdict_sidecar(worktree)

    assert verdict is not None
    assert "BLOCKED" in verdict
    assert "Critical security issue" in verdict

    print("✓ Sidecar handles BLOCKED verdicts")


def test_verdict_sidecar_ignores_invalid_json(tmp_path):
    """Invalid JSON in sidecar should return None, not raise."""
    adapter = RunnerAdapter(provider="opencode")
    worktree = tmp_path / "agents" / "bd-bad-json" / "agent-skills"
    sidecar_dir = worktree / ".dx-loop"
    sidecar_dir.mkdir(parents=True)
    (sidecar_dir / "verdict.json").write_text("not valid json {")

    verdict = adapter.extract_verdict_sidecar(worktree)

    assert verdict is None

    print("✓ Invalid sidecar JSON is handled gracefully")


def test_verdict_sidecar_ignores_unknown_verdict(tmp_path):
    """Sidecar with unknown verdict string should return None."""
    adapter = RunnerAdapter(provider="opencode")
    worktree = tmp_path / "agents" / "bd-unknown" / "agent-skills"
    sidecar_dir = worktree / ".dx-loop"
    sidecar_dir.mkdir(parents=True)
    (sidecar_dir / "verdict.json").write_text(
        json.dumps({"verdict": "MAYBE", "detail": "Not sure"})
    )

    verdict = adapter.extract_verdict_sidecar(worktree)

    assert verdict is None

    print("✓ Unknown verdict in sidecar is ignored")


def test_refresh_task_status_returns_none_for_unknown_task():
    """refresh_task_status should return None for tasks not in the wave."""
    manager = BeadsWaveManager()
    result = manager.refresh_task_status("bd-unknown")
    assert result is None

    print("✓ refresh_task_status returns None for unknown tasks")


def test_refresh_task_status_survives_beads_timeout(monkeypatch):
    """refresh_task_status should return None on Beads timeout, not crash."""
    manager = BeadsWaveManager()
    manager.tasks["bd-timeout"] = BeadsTask(
        beads_id="bd-timeout",
        title="Timeout task",
        status="open",
    )

    def fake_run(*args, **kwargs):
        raise subprocess.TimeoutExpired(cmd=args[0], timeout=5)

    monkeypatch.setattr(subprocess, "run", fake_run)

    result = manager.refresh_task_status("bd-timeout")

    assert result is None
    assert "bd-timeout" not in manager.completed

    print("✓ refresh_task_status survives Beads timeout gracefully")


def test_external_close_stops_live_implement_job(tmp_path, monkeypatch):
    """External close should stop a still-running implement job before terminal transition."""
    wave_id = "wave-stop-live-implement"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-running-close": BeadsTask(
            beads_id="bd-running-close",
            title="Running then closed",
            repo="agent-skills",
            dependencies=[],
        )
    }
    loop.beads_manager.layers = [["bd-running-close"]]
    loop.baton_manager.start_implement("bd-running-close", run_id="run-1")
    loop.scheduler.state.mark_dispatched("bd-running-close", "implement")

    stop_calls = []

    def fake_stop(beads_id):
        stop_calls.append(beads_id)
        return True

    loop.implement_runner.stop = fake_stop
    loop.implement_runner.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="healthy",
        reason_code="recent_log_activity",
    )

    def fake_run(cmd, **kwargs):
        beads_id = cmd[2]
        payload = [
            {
                "id": beads_id,
                "status": "closed",
                "close_reason": "Merged manually",
            }
        ]
        return subprocess.CompletedProcess(
            cmd, 0, stdout=json.dumps(payload), stderr=""
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    loop._check_progress()

    assert "bd-running-close" in stop_calls, "Live implement job should be stopped"
    baton = loop.baton_manager.get_state("bd-running-close")
    assert baton is not None
    assert baton.phase == BatonPhase.COMPLETE

    print("✓ External close stops live implement job before terminal transition")


def test_external_close_stops_live_review_job(tmp_path, monkeypatch):
    """External close should stop a still-running review job before terminal transition."""
    wave_id = "wave-stop-live-review"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-review-close": BeadsTask(
            beads_id="bd-review-close",
            title="Review then closed",
            repo="agent-skills",
            dependencies=[],
        )
    }
    loop.baton_manager.start_implement("bd-review-close")
    loop.baton_manager.complete_implement(
        "bd-review-close", pr_url="http://example/1", pr_head_sha="a" * 40
    )
    loop.baton_manager.start_review("bd-review-close", run_id="review-run-1")
    loop.scheduler.state.mark_dispatched("bd-review-close", "review")

    stop_calls = []

    def fake_stop(beads_id):
        stop_calls.append(beads_id)
        return True

    loop.review_runner.stop = fake_stop
    loop.review_runner.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="healthy",
        reason_code="recent_log_activity",
    )

    def fake_run(cmd, **kwargs):
        payload = [
            {
                "id": cmd[2],
                "status": "resolved",
                "close_reason": "Superseded",
            }
        ]
        return subprocess.CompletedProcess(
            cmd, 0, stdout=json.dumps(payload), stderr=""
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    loop._check_progress()

    assert "bd-review-close-review" in stop_calls, "Live review job should be stopped"
    baton = loop.baton_manager.get_state("bd-review-close")
    assert baton is not None
    assert baton.phase == BatonPhase.COMPLETE

    print("✓ External close stops live review job before terminal transition")


def test_external_close_skips_stop_when_job_exited(tmp_path, monkeypatch):
    """External close should not call stop when the runner job already exited."""
    wave_id = "wave-no-stop-exited"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-exited-close": BeadsTask(
            beads_id="bd-exited-close",
            title="Exited then closed",
            repo="agent-skills",
            dependencies=[],
        )
    }
    loop.baton_manager.start_implement("bd-exited-close", run_id="run-1")
    loop.scheduler.state.mark_dispatched("bd-exited-close", "implement")

    stop_calls = []

    def fake_stop(beads_id):
        stop_calls.append(beads_id)
        return True

    loop.implement_runner.stop = fake_stop
    loop.implement_runner.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="exited_ok",
        reason_code="process_exit_with_rc",
    )

    def fake_run(cmd, **kwargs):
        payload = [
            {
                "id": cmd[2],
                "status": "closed",
                "close_reason": "Done",
            }
        ]
        return subprocess.CompletedProcess(
            cmd, 0, stdout=json.dumps(payload), stderr=""
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    loop._check_progress()

    assert stop_calls == [], "stop should not be called for an already-exited job"

    print("✓ External close skips stop when runner job already exited")


def test_refresh_task_status_writes_correct_repo_in_metadata(tmp_path, monkeypatch):
    """refresh_task_status should use inferred repo, not title, in metadata."""
    manager = BeadsWaveManager()
    manager.tasks["bd-repo-test"] = BeadsTask(
        beads_id="bd-repo-test",
        title="Agent-skills: harden dx-loop",
        status="open",
        repo="agent-skills",
    )

    def fake_run(cmd, **kwargs):
        payload = [
            {
                "id": "bd-repo-test",
                "title": "Agent-skills: harden dx-loop",
                "status": "closed",
                "close_reason": "PR #434",
            }
        ]
        return subprocess.CompletedProcess(
            cmd, 0, stdout=json.dumps(payload), stderr=""
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    result = manager.refresh_task_status("bd-repo-test")

    assert result == "closed"
    meta = manager.get_dependency_metadata("bd-repo-test")
    assert meta["repo"] == "agent-skills", (
        f"Expected inferred repo, got: {meta['repo']}"
    )
    assert meta["title"] == "Agent-skills: harden dx-loop"

    print("✓ refresh_task_status writes correct repo in metadata")


def test_review_prompt_instructs_verdict_sidecar():
    """Default review prompt should instruct the reviewer to write .dx-loop/verdict.json."""
    loop = DxLoop("wave-test")
    loop.beads_manager.tasks["bd-sidecar-wire"] = BeadsTask(
        beads_id="bd-sidecar-wire",
        title="Agent-skills: wire sidecar",
        description="Ensure reviewers emit the verdict sidecar.",
        repo="agent-skills",
    )

    prompt = loop._generate_review_prompt(
        "bd-sidecar-wire",
        "https://github.com/stars-end/agent-skills/pull/434",
        "a" * 40,
    )

    assert ".dx-loop/verdict.json" in prompt
    assert '"verdict": "APPROVED"' in prompt
    assert '"detail"' in prompt
    assert "backward compatibility" in prompt

    print("✓ Default review prompt instructs verdict sidecar output")


def test_external_close_stop_failure_quarantines_task(tmp_path, monkeypatch):
    """When runner.stop() returns False, the task must be quarantined
    and NOT advanced to COMPLETE."""
    wave_id = "wave-stop-fail"
    loop = DxLoop(wave_id, config={"cadence_seconds": 0})
    loop.wave_dir = tmp_path / "waves" / wave_id
    loop.state_file = loop.wave_dir / "loop_state.json"
    loop.beads_manager.tasks = {
        "bd-stop-fail": BeadsTask(
            beads_id="bd-stop-fail",
            title="Agent-skills: stop failure test",
            repo="agent-skills",
            dependencies=[],
        )
    }
    loop.baton_manager.start_implement("bd-stop-fail", run_id="run-1")
    loop.scheduler.state.mark_dispatched("bd-stop-fail", "implement")

    loop.implement_runner.stop = lambda beads_id: False
    loop.implement_runner.check = lambda beads_id: RunnerTaskState(
        beads_id=beads_id,
        state="healthy",
        reason_code="recent_log_activity",
    )

    def fake_run(cmd, **kwargs):
        payload = [
            {
                "id": cmd[2],
                "status": "closed",
                "close_reason": "Done",
            }
        ]
        return subprocess.CompletedProcess(
            cmd, 0, stdout=json.dumps(payload), stderr=""
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    loop._check_progress()

    baton = loop.baton_manager.get_state("bd-stop-fail")
    assert baton is not None, "Baton state should exist"
    assert baton.phase != BatonPhase.COMPLETE, (
        "Baton must NOT be COMPLETE when stop fails"
    )
    assert baton.metadata.get("blocker_code") == "external_close_stop_failed", (
        f"Expected quarantine blocker, got: {baton.metadata.get('blocker_code')}"
    )
    assert "bd-stop-fail" in loop.scheduler.state.blocked_beads_ids, (
        "Task should be in blocked set"
    )

    print("✓ Stop failure quarantines task and blocks terminal transition")
