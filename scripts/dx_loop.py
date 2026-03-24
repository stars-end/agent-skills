#!/usr/bin/env python3
"""
dx-loop v1.1 - Complete PR-aware orchestration surface

FIXES from PR #322 review:
- P0: Active work no longer redispatched every cadence (scheduler.py)
- P1: Blocked notifications emit on FIRST occurrence, suppress repeats (state_machine.py)
- P1: State persistence is symmetric and durable for unattended restart (this file)

This version uses:
- DxLoopScheduler for no-duplicate-dispatch
- RunnerAdapter for governed dx-runner integration
- Full state persistence across restart
"""

from __future__ import annotations
import argparse, json, os, subprocess, sys, time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Dict, Any, List

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent / "lib"))

from dx_loop import (
    LoopState,
    BlockerCode,
    LoopStateMachine,
    LoopStateTracker,
    BatonPhase,
    BatonManager,
    ReviewVerdict,
    BatonState,
    BlockerClassifier,
    BlockerState,
    PRContractEnforcer,
    PRArtifact,
    BeadsWaveManager,
    NotificationManager,
)
from dx_loop.scheduler import DxLoopScheduler, SchedulerState
from dx_loop.runner_adapter import RunnerAdapter, RunnerTaskState, RunnerStartResult

VERSION = "1.3.0"
ARTIFACT_BASE = Path("/tmp/dx-loop")
DEFAULT_CONFIG = {
    "max_attempts": 3,
    "max_revisions": 3,
    "max_parallel": 2,
    "cadence_seconds": 600,  # 10 minutes
    "provider": "opencode",
    "implement_provider": None,  # defaults to provider if not set (Pillar C)
    "review_provider": None,  # defaults to provider if not set (Pillar C)
    "require_review": True,
    "exit_on_zero_dispatch_start": True,
    "worktree_base": "/tmp/agents",  # Base dir for worktrees
}

RUNNER_LIFECYCLE_DEFECT_REASONS = frozenset(
    {
        "monitor_no_rc_file",
        "late_finalize_no_rc",
    }
)


def load_config_file(path: Optional[str]) -> Dict[str, Any]:
    """Load and merge a YAML config file into DEFAULT_CONFIG."""
    config = dict(DEFAULT_CONFIG)
    if not path:
        return config
    config_path = Path(path)
    if not config_path.exists():
        print(f"WARN: config file not found: {config_path}", file=sys.stderr)
        return config
    try:
        import yaml

        with open(config_path) as f:
            overrides = yaml.safe_load(f) or {}
        for key, value in overrides.items():
            if (
                isinstance(value, dict)
                and key in config
                and isinstance(config[key], dict)
            ):
                config[key] = {**config[key], **value}
            else:
                config[key] = value
        print(f"Loaded config from {config_path}")
    except ImportError:
        print("WARN: PyYAML not installed, skipping --config", file=sys.stderr)
    except Exception as exc:
        print(f"WARN: failed to load config: {exc}", file=sys.stderr)
    return config


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class DxLoop:
    """
    Main dx-loop orchestration class - v1.1 with fixes

    Integrates:
    - DxLoopScheduler for no-duplicate-dispatch (P0 fix)
    - RunnerAdapter for governed dx-runner integration
    - Full symmetric state persistence (P1 fix)
    - Fixed notification logic (P1 fix)
    """

    def __init__(self, wave_id: str, config: Optional[Dict[str, Any]] = None):
        self.wave_id = wave_id
        self.config = {**DEFAULT_CONFIG, **(config or {})}

        # Initialize components
        self.state_machine = LoopStateMachine()
        self.baton_manager = BatonManager(
            max_attempts=self.config["max_attempts"],
            max_revisions=self.config["max_revisions"],
        )
        self.pr_enforcer = PRContractEnforcer()
        self.beads_manager = BeadsWaveManager()
        self.blocker_classifier = BlockerClassifier()
        self.notification_manager = NotificationManager()

        # NEW: Scheduler and runner adapter (P0 fix)
        self.scheduler = DxLoopScheduler(cadence_seconds=self.config["cadence_seconds"])

        # Pillar C: Phase-aware provider routing
        self.implement_provider = (
            self.config.get("implement_provider") or self.config["provider"]
        )
        self.review_provider = (
            self.config.get("review_provider") or self.config["provider"]
        )
        self.implement_runner = RunnerAdapter(
            provider=self.implement_provider,
            beads_repo_path=self.beads_manager.beads_repo_path,
        )
        self.review_runner = RunnerAdapter(
            provider=self.review_provider,
            beads_repo_path=self.beads_manager.beads_repo_path,
        )
        # Backward compat: default runner_adapter is the implement runner
        self.runner_adapter = self.implement_runner

        # Artifact paths
        self.wave_dir = ARTIFACT_BASE / "waves" / wave_id
        self.state_file = self.wave_dir / "loop_state.json"
        self.log_dir = self.wave_dir / "logs"
        self.outcome_dir = self.wave_dir / "outcomes"
        self.wave_status: Dict[str, Any] = {
            "state": LoopState.PENDING.value,
            "blocker_code": None,
            "reason": "wave initialized",
            "blocked_details": [],
            "dispatchable_tasks": [],
        }

    def bootstrap_epic(self, epic_id: str) -> bool:
        """
        Bootstrap wave from Beads epic

        Loads epic tasks and computes topological layers.
        """
        print(f"Loading epic {epic_id} from Beads...")
        tasks = self.beads_manager.load_epic_tasks(epic_id)

        if not tasks:
            print(f"ERROR: No tasks found for epic {epic_id}", file=sys.stderr)
            return False

        print(f"Found {len(tasks)} tasks")

        # Compute execution layers
        layers = self.beads_manager.compute_layers()
        print(f"Computed {len(layers)} execution layers")

        for i, layer in enumerate(layers):
            print(f"  Layer {i}: {len(layer)} task(s)")

        # Save state
        self._save_state()
        return True

    def run_loop(self, max_iterations: int = 100) -> bool:
        """
        Run main loop cycle with scheduler (P0 fix)

        Uses DxLoopScheduler to prevent duplicate dispatch.
        """
        # Load previous state if exists
        self._load_state()

        iteration = 0

        while iteration < max_iterations:
            iteration += 1
            print(f"\n=== Iteration {iteration} ===")

            # Clear one-cycle cooldown blockers only for bounded redispatch cases.
            if (
                self.wave_status.get("state")
                == LoopState.DETERMINISTIC_REDISPATCH_NEEDED.value
            ):
                self.scheduler.state.blocked_beads_ids.clear()

            # PHASE 1: Wake-up - Check time
            now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            print(f"Wake-up at {now}")

            # PHASE 2: Poll active task progress
            self._check_progress()

            # PHASE 3: Get ready tasks (respecting scheduler state)
            readiness = self.beads_manager.describe_wave_readiness()
            ready = readiness.ready or None

            if not ready:
                if not self.beads_manager.has_pending_tasks():
                    print("Wave complete - no pending tasks")
                    self._set_wave_status(
                        LoopState.COMPLETED,
                        None,
                        "Wave complete - no pending tasks",
                    )
                    self._save_state()
                    return True
                if readiness.waiting_on_dependencies:
                    blocked_ids = [
                        item["beads_id"] for item in readiness.waiting_on_dependencies
                    ]
                    self.scheduler.state.blocked_beads_ids = set(blocked_ids)
                    blocked_reason = f"No dispatches: waiting on dependencies for {len(blocked_ids)} task(s)"
                    if self._should_exit_blocked_at_start(iteration):
                        blocked_reason = (
                            f"Initial frontier blocked with {len(blocked_ids)} task(s); "
                            "exiting without resident loop"
                        )
                    self._set_wave_status(
                        LoopState.WAITING_ON_DEPENDENCY,
                        BlockerCode.WAITING_ON_DEPENDENCY,
                        blocked_reason,
                        blocked_details=readiness.waiting_on_dependencies,
                    )
                    print(
                        f"No ready tasks: waiting on dependencies for {len(blocked_ids)} task(s)"
                    )
                    for item in readiness.waiting_on_dependencies[:3]:
                        deps = ", ".join(item["unmet_dependencies"])
                        print(f"  {item['beads_id']} waiting on: {deps}")
                    if self._should_exit_blocked_at_start(iteration):
                        print(
                            "Initial frontier has zero dispatchable tasks; exiting "
                            "without resident loop"
                        )
                        self._save_state()
                        return True
                else:
                    self._set_wave_status(
                        LoopState.PENDING,
                        None,
                        "No ready tasks, waiting for next cadence",
                    )
                    print("No ready tasks, waiting for next cadence...")
            else:
                # FILTER OUT ALREADY ACTIVE TASKS (P0 fix with phase-awareness)
                dispatchable = []
                for tid in ready:
                    # Get baton phase to determine expected dispatch phase
                    baton_state = self.baton_manager.get_state(tid)
                    if baton_state and baton_state.phase == BatonPhase.REVIEW:
                        expected_phase = "review"
                    else:
                        expected_phase = "implement"

                    # Check if THIS phase is already active
                    if not self.scheduler.state.is_active(tid, expected_phase):
                        if not self.scheduler.state.is_completed(
                            tid
                        ) and not self.scheduler.state.is_blocked(tid):
                            dispatchable.append((tid, expected_phase))

                if dispatchable:
                    max_parallel = self.config.get("max_parallel", 2)
                    active_count = len(self.scheduler.state.active_beads_ids)
                    dispatch_capacity = max(0, max_parallel - active_count)
                    capped = dispatchable[:dispatch_capacity]
                    capacity_blocked = False
                    successful_dispatches = []
                    print(
                        f"Dispatching {len(capped)}/{len(dispatchable)} task(s) "
                        f"(active={active_count}, max_parallel={max_parallel})"
                    )
                    for beads_id, phase in capped:
                        if self._dispatch_task(beads_id, phase):
                            self.scheduler.state.mark_dispatched(beads_id, phase)
                            # Persist immediately so status surfaces reflect the new active task.
                            self._save_state()
                            successful_dispatches.append(beads_id)
                        elif self.wave_status.get("blocker_code") == "run_blocked":
                            details = self.wave_status.get("blocked_details", [])
                            reason_codes = {
                                d.get("reason_code")
                                for d in details
                                if d.get("beads_id") == beads_id
                            }
                            if "dx_runner_provider_capacity_blocked" in reason_codes:
                                capacity_blocked = True
                                print(
                                    "Provider at capacity, stopping dispatch "
                                    "for this cycle",
                                    file=sys.stderr,
                                )
                                break
                    if capacity_blocked:
                        self._set_wave_status(
                            LoopState.RUN_BLOCKED,
                            BlockerCode.RUN_BLOCKED,
                            f"Provider at capacity after {len(successful_dispatches)} dispatch(es); "
                            f"remaining tasks deferred to next cadence",
                            blocked_details=self.wave_status.get("blocked_details", []),
                        )
                    elif successful_dispatches:
                        self._set_wave_status(
                            LoopState.IN_PROGRESS_HEALTHY,
                            None,
                            f"Dispatching {len(successful_dispatches)} task(s)",
                            dispatchable_tasks=successful_dispatches,
                        )
                    elif self._should_exit_failed_initial_dispatch(iteration):
                        print(
                            "Initial dispatch failed before any run started; "
                            "exiting without resident loop"
                        )
                        self.wave_status["reason"] = (
                            f"{self.wave_status.get('reason', 'Dispatch failed')} "
                            "[exiting without resident loop]"
                        )
                        self._save_state()
                        return False
                else:
                    blocked_ready = [
                        tid for tid in ready if self.scheduler.state.is_blocked(tid)
                    ]
                    if blocked_ready:
                        exhausted = []
                        for blocked_id in blocked_ready:
                            blocked_state = self.baton_manager.get_state(blocked_id)
                            if not blocked_state:
                                continue
                            failure_reason = blocked_state.metadata.get("failure_reason")
                            if failure_reason in {
                                "max_revisions_exceeded",
                                "max_attempts_exceeded",
                            }:
                                exhausted.append(
                                    {
                                        "beads_id": blocked_id,
                                        "phase": blocked_state.phase.value,
                                        "reason_code": failure_reason,
                                        "attempt": blocked_state.attempt,
                                        "max_attempts": blocked_state.max_attempts,
                                        "revision_count": blocked_state.revision_count,
                                        "max_revisions": blocked_state.max_revisions,
                                    }
                                )

                        if exhausted:
                            self._set_wave_status(
                                LoopState.NEEDS_DECISION,
                                BlockerCode.NEEDS_DECISION,
                                (
                                    f"{len(exhausted)} ready task(s) exhausted review/attempt "
                                    "bounds; operator decision required"
                                ),
                                blocked_details=exhausted,
                                dispatchable_tasks=blocked_ready,
                            )
                        elif self.wave_status.get("blocker_code") not in {
                            BlockerCode.RUN_BLOCKED.value,
                            BlockerCode.REVIEW_BLOCKED.value,
                            BlockerCode.KICKOFF_ENV_BLOCKED.value,
                            BlockerCode.NEEDS_DECISION.value,
                        }:
                            self._set_wave_status(
                                LoopState.RUN_BLOCKED,
                                BlockerCode.RUN_BLOCKED,
                                (
                                    f"{len(blocked_ready)} ready task(s) are blocked, "
                                    "waiting for next cadence"
                                ),
                                blocked_details=[
                                    {
                                        "beads_id": blocked_id,
                                        "phase": (
                                            self.baton_manager.get_state(blocked_id).phase.value
                                            if self.baton_manager.get_state(blocked_id)
                                            else "unknown"
                                        ),
                                    }
                                    for blocked_id in blocked_ready
                                ],
                                dispatchable_tasks=blocked_ready,
                            )
                        print(
                            f"{len(blocked_ready)} ready task(s) are blocked, waiting for next cadence..."
                        )
                    else:
                        self._set_wave_status(
                            LoopState.IN_PROGRESS_HEALTHY,
                            None,
                            "All ready tasks already active, waiting for progress",
                            dispatchable_tasks=ready,
                        )
                        print(f"All ready tasks already active, waiting...")

            # Save state after each iteration
            self._save_state()

            # Sleep until next cadence
            time.sleep(self.config["cadence_seconds"])

        return False

    def _should_exit_blocked_at_start(self, iteration: int) -> bool:
        """
        Exit early when the first frontier is fully blocked.

        This prevents long-lived resident loops from masquerading as useful
        implementation progress when a wave starts with zero dispatchable work.
        """
        return (
            iteration == 1
            and self.config.get("exit_on_zero_dispatch_start", True)
            and self.scheduler.state.dispatch_count == 0
            and not self.scheduler.state.active_beads_ids
        )

    def _should_exit_failed_initial_dispatch(self, iteration: int) -> bool:
        """Exit early if the first dispatch attempt fails before any run exists."""
        return (
            iteration == 1
            and self.scheduler.state.dispatch_count == 0
            and not self.scheduler.state.active_beads_ids
            and self.wave_status.get("state")
            in {
                LoopState.KICKOFF_ENV_BLOCKED.value,
                LoopState.RUN_BLOCKED.value,
            }
        )

    def adopt_running_jobs(self) -> list[str]:
        """
        Probe dx-runner for already-running jobs and adopt them into the scheduler.

        On restart, dx-runner may have live jobs that this loop instance doesn't
        know about. This prevents misclassifying live work as 'blocked' or
        starting duplicate dispatches.

        Safety constraints:
        - Only adopts jobs that are currently RUNNING (not exited_ok, exited_err, etc).
        - Rebuilds baton state so that _check_progress can poll the right phase.
        - Keys scheduler under the base beads_id (not bd-*-review) so
          progress polling and duplicate-dispatch work correctly.
        - Probes the correct runner for the task's baton phase:
          REVIEW tasks are checked on review_runner (bd-<id>-review),
          IMPLEMENT/IDLE tasks are checked on implement_runner.
        """
        adopted: list[str] = []
        for beads_id in list(self.beads_manager.tasks.keys()):
            if self.scheduler.state.is_completed(beads_id):
                continue

            baton_state = self.baton_manager.get_state(beads_id)
            if baton_state and baton_state.phase in (
                BatonPhase.COMPLETE,
                BatonPhase.FAILED,
                BatonPhase.MANUAL_TAKEOVER,
            ):
                continue

            is_running = False
            phase = "implement"

            if baton_state and baton_state.phase == BatonPhase.REVIEW:
                review_beads_id = f"{beads_id}-review"
                task_state = self.review_runner.check(review_beads_id)
                if task_state and task_state.is_running():
                    is_running = True
                    phase = "review"
            else:
                task_state = self.implement_runner.check(beads_id)
                if task_state and task_state.is_running():
                    is_running = True
                    phase = "implement"

            if not is_running:
                continue

            if not baton_state or baton_state.phase == BatonPhase.IDLE:
                self.baton_manager.start_implement(
                    beads_id,
                    run_id=f"adopted-{beads_id}",
                )
            elif phase == "review" and baton_state.phase != BatonPhase.REVIEW:
                self.baton_manager.start_review(
                    beads_id,
                    run_id=f"adopted-{beads_id}-review",
                )

            self.scheduler.state.mark_dispatched(beads_id, phase)
            self.scheduler.state.blocked_beads_ids.discard(beads_id)
            adopted.append(beads_id)

        return adopted

    def _dispatch_task(self, beads_id: str, phase: str = "implement") -> bool:
        """Dispatch a single task through implement/review cycle"""
        # Check baton phase
        baton_state = self.baton_manager.get_state(beads_id)
        next_action = self.baton_manager.get_next_action(beads_id)

        if next_action == "manual_takeover":
            print(f"Task {beads_id} is under manual takeover, skipping dispatch")
            return False
        elif next_action == "start_implement":
            dep_block = self._check_dependency_artifacts(beads_id)
            if dep_block:
                print(f"Task {beads_id} blocked: {dep_block}")
                self.scheduler.state.mark_blocked(beads_id)
                return False
            return self._start_implement(beads_id)
        elif next_action == "start_review":
            return self._start_review(beads_id)
        elif next_action == "complete":
            print(f"Task {beads_id} already complete")
            self.scheduler.state.mark_completed(beads_id)
            return True
        else:
            print(f"Task {beads_id} blocked: {next_action}")
            self.scheduler.state.mark_blocked(beads_id)
            return False

    def _get_worktree_path(self, beads_id: str) -> Path:
        """
        Compute worktree path for a beads_id (P0 fix)

        Uses standard /tmp/agents/<beads-id>/<repo> pattern.
        Falls back to agent-skills only when repo inference is unavailable.
        """
        task = self.beads_manager.tasks.get(beads_id)
        repo = "agent-skills"  # Default repo

        if task and getattr(task, "repo", None):
            repo = task.repo

        worktree_base = Path(self.config.get("worktree_base", "/tmp/agents"))
        return worktree_base / beads_id / repo

    def _ensure_worktree(self, beads_id: str) -> Optional[Path]:
        """Ensure the task worktree exists before dispatch."""
        worktree = self._get_worktree_path(beads_id)
        if worktree.is_dir():
            return worktree

        task = self.beads_manager.tasks.get(beads_id)
        repo = getattr(task, "repo", None) or worktree.name
        try:
            result = subprocess.run(
                ["dx-worktree", "create", beads_id, repo],
                capture_output=True,
                text=True,
                timeout=120,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
            self._set_wave_status(
                LoopState.KICKOFF_ENV_BLOCKED,
                BlockerCode.KICKOFF_ENV_BLOCKED,
                f"Failed to create worktree for {beads_id}: {exc}",
                blocked_details=[
                    {
                        "beads_id": beads_id,
                        "phase": "worktree",
                        "reason_code": "dx_worktree_create_failed",
                        "detail": str(exc),
                    }
                ],
            )
            return None

        if result.returncode != 0:
            detail = (
                result.stderr.strip()
                or result.stdout.strip()
                or "dx-worktree create failed"
            )
            self._set_wave_status(
                LoopState.KICKOFF_ENV_BLOCKED,
                BlockerCode.KICKOFF_ENV_BLOCKED,
                f"Failed to create worktree for {beads_id}: {detail}",
                blocked_details=[
                    {
                        "beads_id": beads_id,
                        "phase": "worktree",
                        "reason_code": "dx_worktree_create_failed",
                        "detail": detail,
                    }
                ],
            )
            return None

        created_path = Path(
            (result.stdout.strip().splitlines() or [str(worktree)])[-1]
        ).expanduser()
        if created_path.is_dir():
            return created_path
        if worktree.is_dir():
            return worktree

        self._set_wave_status(
            LoopState.KICKOFF_ENV_BLOCKED,
            BlockerCode.KICKOFF_ENV_BLOCKED,
            f"dx-worktree reported success but worktree missing for {beads_id}",
            blocked_details=[
                {
                    "beads_id": beads_id,
                    "phase": "worktree",
                    "reason_code": "dx_worktree_missing_after_create",
                    "detail": str(worktree),
                }
            ],
        )
        return None

    def _start_implement(self, beads_id: str) -> bool:
        """Start implement phase via RunnerAdapter (P0 fix: explicit worktree)"""
        worktree = self._ensure_worktree(beads_id)
        if not worktree:
            return False

        prompt = self._resolve_prompt(beads_id, "implement", worktree)

        dep_section = self._format_dependency_context(beads_id)
        if dep_section:
            prompt = prompt + "\n\n" + dep_section

        prompt_file = ARTIFACT_BASE / "prompts" / f"{beads_id}.implement.prompt"
        prompt_file.parent.mkdir(parents=True, exist_ok=True)
        prompt_file.write_text(prompt)

        run_id = f"{beads_id}-{now_utc().replace(':', '-').replace('T', '-')}"

        result = self.implement_runner.start(beads_id, prompt_file, worktree=worktree)

        if result.ok:
            self.baton_manager.start_implement(beads_id, run_id=run_id)
            print(
                f"Started implement for {beads_id} (run_id={run_id}, provider={self.implement_provider})"
            )
            return True
        else:
            self._handle_dispatch_start_failure(beads_id, "implement", result)
            return False

    def _start_review(self, beads_id: str) -> bool:
        """Start review phase via RunnerAdapter (P0 fix: explicit worktree)"""
        baton_state = self.baton_manager.get_state(beads_id)
        if not baton_state or not baton_state.pr_url:
            print(
                f"ERROR: No PR artifact for {beads_id}, cannot review", file=sys.stderr
            )
            return False

        worktree = self._ensure_worktree(beads_id)
        if not worktree:
            return False

        prompt = self._resolve_prompt(beads_id, "review", worktree)
        prompt_file = ARTIFACT_BASE / "prompts" / f"{beads_id}.review.prompt"
        prompt_file.parent.mkdir(parents=True, exist_ok=True)
        prompt_file.write_text(prompt)

        review_beads_id = f"{beads_id}-review"
        run_id = f"{review_beads_id}-{now_utc().replace(':', '-').replace('T', '-')}"

        result = self.review_runner.start(
            review_beads_id, prompt_file, worktree=worktree
        )

        if result.ok:
            self.baton_manager.start_review(beads_id, run_id=run_id)
            print(
                f"Started review for {beads_id} (run_id={run_id}, provider={self.review_provider})"
            )
            return True
        else:
            self._handle_dispatch_start_failure(beads_id, "review", result)
            return False

    def _handle_dispatch_start_failure(
        self,
        beads_id: str,
        phase: str,
        result: RunnerStartResult,
    ) -> None:
        """Convert failed dx-runner starts into truthful wave state and output."""
        start_reason = result.detail or result.reason_code or "dx-runner start failed"
        blocker_state = LoopState.RUN_BLOCKED
        blocker_code = BlockerCode.RUN_BLOCKED

        if result.reason_code in {
            "dx_runner_missing",
            "dx_runner_shell_preflight_failed",
            "dx_runner_preflight_failed",
            "dx_runner_permission_denied",
            "dx_runner_model_unavailable",
            "dx_runner_start_timeout",
        }:
            blocker_state = LoopState.KICKOFF_ENV_BLOCKED
            blocker_code = BlockerCode.KICKOFF_ENV_BLOCKED

        self.scheduler.state.mark_blocked(beads_id)
        self._set_wave_status(
            blocker_state,
            blocker_code,
            f"Failed to start {phase} for {beads_id}: {start_reason}",
            blocked_details=[
                {
                    "beads_id": beads_id,
                    "phase": phase,
                    "reason_code": result.reason_code,
                    "detail": start_reason,
                    "command": result.command,
                    "returncode": result.returncode,
                }
            ],
        )
        print(
            f"ERROR: Failed to start {phase} for {beads_id} "
            f"(reason={result.reason_code or 'unknown'}, rc={result.returncode})",
            file=sys.stderr,
        )
        if start_reason:
            print(f"  {start_reason}", file=sys.stderr)

    def _check_progress(self):
        """Check progress of all active tasks via RunnerAdapter"""
        for beads_id, baton_state in list(self.baton_manager.baton_states.items()):
            if baton_state.phase in (
                BatonPhase.COMPLETE,
                BatonPhase.FAILED,
                BatonPhase.MANUAL_TAKEOVER,
            ):
                continue

            if baton_state.phase == BatonPhase.IMPLEMENT:
                self._check_implement_progress(beads_id)
            elif baton_state.phase == BatonPhase.REVIEW:
                self._check_review_progress(beads_id)

    def _check_implement_progress(self, beads_id: str):
        """Check implement phase progress via RunnerAdapter"""
        task_state = self.implement_runner.check(beads_id)

        if not task_state or task_state.state == "missing":
            return

        # Check for completion
        if task_state.is_complete():
            transcript = self.implement_runner.extract_agent_output(beads_id) or ""
            implementation_return = self.pr_enforcer.extract_implementation_return(
                transcript
            )
            if implementation_return:
                self.pr_enforcer.register_implementation_return(
                    beads_id, implementation_return
                )

            artifacts = self.implement_runner.extract_pr_artifacts(beads_id)
            if not artifacts and implementation_return:
                artifacts = (
                    implementation_return.pr_url,
                    implementation_return.pr_head_sha,
                )

            if artifacts:
                pr_url, pr_head_sha = artifacts
                # Register artifact and transition to review
                self.pr_enforcer.register_artifact(beads_id, pr_url, pr_head_sha)

                # P0 FIX: Clear "implement" phase to allow review dispatch
                self.scheduler.state.clear_phase(beads_id, "implement")

                if self.config["require_review"]:
                    self.baton_manager.complete_implement(
                        beads_id,
                        pr_url=pr_url,
                        pr_head_sha=pr_head_sha,
                    )
                    print(f"Implement complete for {beads_id}, transitioning to review")
                else:
                    self.baton_manager.baton_states[
                        beads_id
                    ].phase = BatonPhase.COMPLETE
                    self.beads_manager.mark_completed(beads_id)
                    self.scheduler.state.mark_completed(beads_id)
                    print(f"Implement complete for {beads_id} (no review required)")
            else:
                reason = task_state.reason_code or "missing_implementation_return"

                if reason in RUNNER_LIFECYCLE_DEFECT_REASONS:
                    self._set_wave_status(
                        LoopState.KICKOFF_ENV_BLOCKED,
                        BlockerCode.KICKOFF_ENV_BLOCKED,
                        (
                            f"Runner lifecycle defect for {beads_id}: {reason}. "
                            f"This is not a task failure — the execution harness did not "
                            f"capture an exit code. Check dx-runner logs and shell/toolchain "
                            f"on this host."
                        ),
                        blocked_details=[
                            {
                                "beads_id": beads_id,
                                "phase": "implement",
                                "reason_code": reason,
                                "detail": (
                                    f"Runner monitor could not find rc file. "
                                    f"Root cause: dx-runner completion monitor or shell "
                                    f"wrapper failed to capture the child exit code. "
                                    f"Check: bash version, dx-runner adapter logs, and "
                                    f"/tmp/dx-runner/{self.config['provider']}/{beads_id}.* artifacts."
                                ),
                            }
                        ],
                    )
                    self.scheduler.state.mark_blocked(beads_id)
                    notification = self.notification_manager.create_notification(
                        self.blocker_classifier.classify(
                            reason,
                            beads_id=beads_id,
                            wave_id=self.wave_id,
                            metadata={"runner_lifecycle_defect": True},
                            has_pr_artifacts=False,
                        )
                    )
                    if notification:
                        print(notification.format_cli())
                else:
                    blocker = self.blocker_classifier.classify(
                        reason,
                        beads_id=beads_id,
                        wave_id=self.wave_id,
                        metadata={
                            "has_pr_artifacts": bool(artifacts),
                            "has_implementation_return": bool(implementation_return),
                        },
                        has_pr_artifacts=False,
                    )

                    task = self.beads_manager.tasks.get(beads_id)
                    baton = self.baton_manager.get_state(beads_id)

                    notification = self.notification_manager.create_notification(
                        blocker,
                        task_title=task.title if task else None,
                        attempt=baton.attempt if baton else None,
                        max_attempts=baton.max_attempts if baton else None,
                    )
                    if notification:
                        print(notification.format_cli())

                    self.scheduler.state.mark_blocked(beads_id)

                    if blocker.code == BlockerCode.DETERMINISTIC_REDISPATCH_NEEDED:
                        baton_state = self.baton_manager.record_implement_retry(
                            beads_id, task_state.reason_code
                        )
                        if baton_state.phase == BatonPhase.FAILED:
                            self._set_wave_status(
                                LoopState.NEEDS_DECISION,
                                BlockerCode.NEEDS_DECISION,
                                (
                                    f"Implement retries exhausted for {beads_id} after "
                                    f"{task_state.reason_code or 'unknown failure'}"
                                ),
                                blocked_details=[
                                    {
                                        "beads_id": beads_id,
                                        "phase": "implement",
                                        "reason_code": task_state.reason_code,
                                        "detail": baton_state.metadata.get(
                                            "failure_reason"
                                        ),
                                        "attempt": baton_state.attempt,
                                        "max_attempts": baton_state.max_attempts,
                                    }
                                ],
                            )
                        else:
                            self._set_wave_status(
                                LoopState.DETERMINISTIC_REDISPATCH_NEEDED,
                                BlockerCode.DETERMINISTIC_REDISPATCH_NEEDED,
                                (
                                    f"Implement attempt {baton_state.attempt - 1} for {beads_id} "
                                    f"failed with {task_state.reason_code}; retrying next cadence"
                                ),
                                blocked_details=[
                                    {
                                        "beads_id": beads_id,
                                        "phase": "implement",
                                        "reason_code": task_state.reason_code,
                                        "attempt": baton_state.attempt,
                                        "max_attempts": baton_state.max_attempts,
                                    }
                                ],
                            )
                    else:
                        self._set_wave_status(
                            LoopState(blocker.code.value),
                            blocker.code,
                            blocker.message,
                            blocked_details=[
                                {
                                    "beads_id": beads_id,
                                    "phase": "implement",
                                    "reason_code": task_state.reason_code,
                                    "attempt": baton.attempt if baton else None,
                                    "max_attempts": baton.max_attempts if baton else None,
                                }
                            ],
                        )

    def _check_review_progress(self, beads_id: str):
        """Check review phase progress"""
        review_beads_id = f"{beads_id}-review"
        task_state = self.review_runner.check(review_beads_id)

        if not task_state or task_state.state == "missing":
            return

        if task_state.is_complete():
            verdict = self._parse_review_verdict(
                self.review_runner.report(review_beads_id),
                self.review_runner.extract_review_verdict(review_beads_id),
            )

            if verdict:
                baton_state = self.baton_manager.complete_review(
                    beads_id,
                    verdict,
                    pr_url=self.pr_enforcer.get_artifact(beads_id).pr_url
                    if self.pr_enforcer.get_artifact(beads_id)
                    else None,
                    pr_head_sha=self.pr_enforcer.get_artifact(beads_id).pr_head_sha
                    if self.pr_enforcer.get_artifact(beads_id)
                    else None,
                )

                if baton_state.phase == BatonPhase.COMPLETE:
                    self.beads_manager.mark_completed(beads_id)
                    self.scheduler.state.mark_completed(beads_id)
                    self._set_wave_status(
                        LoopState.MERGE_READY,
                        BlockerCode.MERGE_READY,
                        f"Review APPROVED for {beads_id}, task complete",
                        dispatchable_tasks=[beads_id],
                    )
                    # Persist completion immediately so status is truthful between poll and dispatch.
                    self._save_state()
                    print(f"Review APPROVED for {beads_id}, task complete")

                    # Emit merge_ready notification with handoff context
                    task = self.beads_manager.tasks.get(beads_id)
                    artifact = self.pr_enforcer.get_artifact(beads_id)
                    blocker = self.blocker_classifier.classify(
                        None,
                        beads_id=beads_id,
                        wave_id=self.wave_id,
                        has_pr_artifacts=True,
                        checks_passing=True,
                    )
                    notification = self.notification_manager.create_notification(
                        blocker,
                        pr_url=artifact.pr_url if artifact else None,
                        pr_head_sha=artifact.pr_head_sha if artifact else None,
                        task_title=task.title if task else None,
                    )
                    if notification:
                        print(notification.format_cli())
                elif baton_state.phase == BatonPhase.IMPLEMENT:
                    # P0 FIX: Clear "review" phase to allow revision implement dispatch
                    self.scheduler.state.clear_phase(beads_id, "review")
                    self._save_state()
                    print(
                        f"Review REVISION_REQUIRED for {beads_id}, returning to implement"
                    )
                elif baton_state.phase == BatonPhase.FAILED:
                    self.scheduler.state.clear_phase(beads_id, "review")
                    self.scheduler.state.mark_blocked(beads_id)
                    failure_reason = baton_state.metadata.get(
                        "failure_reason", "review_exhausted"
                    )
                    self._set_wave_status(
                        LoopState.NEEDS_DECISION,
                        BlockerCode.NEEDS_DECISION,
                        (
                            f"Review exhausted for {beads_id} after "
                            f"{failure_reason.replace('_', ' ')}"
                        ),
                        blocked_details=[
                            {
                                "beads_id": beads_id,
                                "phase": "review",
                                "reason_code": failure_reason,
                                "attempt": baton_state.attempt,
                                "max_attempts": baton_state.max_attempts,
                                "revision_count": baton_state.revision_count,
                                "max_revisions": baton_state.max_revisions,
                                "verdict": verdict.value,
                            }
                        ],
                    )
                    self._save_state()
                    print(f"Review verdict for {beads_id}: {verdict.value}")
                else:
                    self._save_state()
                    print(f"Review verdict for {beads_id}: {verdict.value}")
            else:
                self.scheduler.state.clear_phase(beads_id, "review")
                self.scheduler.state.mark_blocked(beads_id)
                self._set_wave_status(
                    LoopState.NEEDS_DECISION,
                    BlockerCode.NEEDS_DECISION,
                    (
                        f"Review completed for {beads_id} without a machine-readable "
                        f"verdict ({task_state.reason_code or 'unknown reason'})"
                    ),
                    blocked_details=[
                        {
                            "beads_id": beads_id,
                            "phase": "review",
                            "reason_code": task_state.reason_code,
                            "detail": (
                                "Terminal review run produced no APPROVED / "
                                "REVISION_REQUIRED / BLOCKED verdict"
                            ),
                        }
                    ],
                )
                self._save_state()
                print(
                    f"Review for {beads_id} ended without a parseable verdict; "
                    "manual inspection required"
                )

    def _parse_review_verdict(
        self,
        report: Optional[Dict[str, Any]],
        raw_verdict: Optional[str] = None,
    ) -> Optional[ReviewVerdict]:
        """Parse review verdict from report"""
        verdict_str = ""
        if report:
            verdict_str = str(report.get("verdict", ""))
        if not verdict_str and raw_verdict:
            verdict_str = raw_verdict
        verdict_str = verdict_str.upper()

        if "APPROVED" in verdict_str:
            return ReviewVerdict.APPROVED
        elif "REVISION_REQUIRED" in verdict_str:
            return ReviewVerdict.REVISION_REQUIRED
        elif "BLOCKED" in verdict_str:
            return ReviewVerdict.BLOCKED

        return None

    def collect_dependency_artifacts(self, beads_id: str) -> List[Dict[str, Any]]:
        """Collect PR artifacts from all completed dependencies (Pillar A)."""
        task = self.beads_manager.tasks.get(beads_id)
        if not task or not task.dependencies:
            return []

        artifacts = []
        for dep_id in task.dependencies:
            if dep_id not in self.beads_manager.completed:
                continue
            artifact = self.pr_enforcer.get_artifact(dep_id)
            if artifact:
                artifacts.append(
                    {
                        "beads_id": dep_id,
                        "pr_url": artifact.pr_url,
                        "pr_head_sha": artifact.pr_head_sha,
                    }
                )
        return artifacts

    def _format_dependency_context(self, beads_id: str) -> str:
        """Format dependency PR artifacts as a prompt section (Pillar A)."""
        dep_artifacts = self.collect_dependency_artifacts(beads_id)
        if not dep_artifacts:
            return ""

        lines = ["## Upstream Dependency Context (Stacked-PR Bootstrap)"]
        lines.append("")
        lines.append("The following upstream dependencies have completed. Branch from")
        lines.append("their PR HEAD SHA(s) to ensure a clean stacked-PR chain:")
        lines.append("")
        for art in dep_artifacts:
            lines.append(
                f"- `{art['beads_id']}`: PR [{art['pr_url']}] SHA `{art['pr_head_sha']}`"
            )
        lines.append("")
        return "\n".join(lines)

    def _check_dependency_artifacts(self, beads_id: str) -> Optional[str]:
        """Block dispatch if upstream deps lack PR artifacts (Pillar A)."""
        task = self.beads_manager.tasks.get(beads_id)
        if not task or not task.dependencies:
            return None

        missing = []
        for dep_id in task.dependencies:
            if dep_id in self.beads_manager.completed:
                if not self.pr_enforcer.has_valid_artifact(dep_id):
                    missing.append(dep_id)
            elif dep_id in self.beads_manager.tasks:
                if not self.pr_enforcer.has_valid_artifact(dep_id):
                    task_status = self.beads_manager.tasks[dep_id].status
                    if task_status.lower() in {
                        "closed",
                        "resolved",
                        "completed",
                        "done",
                    }:
                        missing.append(dep_id)

        if missing:
            return (
                f"Upstream dependency missing PR artifacts: {', '.join(missing)}. "
                "Child tasks should not proceed without upstream PR artifacts."
            )
        return None

    def _generate_implement_prompt(self, beads_id: str) -> str:
        """Generate implementer prompt using prompt-writing + handoff contracts."""
        task = self.beads_manager.tasks.get(beads_id)
        title = task.title if task else beads_id
        repo = task.repo if task and task.repo else "unknown-repo"
        description = (
            task.description or "No additional description provided."
        ).strip()
        dependencies = (
            ", ".join(task.dependencies) if task and task.dependencies else "none"
        )

        return f"""you're a full-stack implementation agent working inside dx-loop:

Use [$tech-lead-handoff](/Users/fengning/agent-skills/core/tech-lead-handoff/SKILL.md) for your final return package.
This prompt follows the structure of [$prompt-writing](/Users/fengning/agent-skills/extended/prompt-writing/SKILL.md).

## DX Global Constraints (Always-On)
1) NO WRITES in canonical clones: `~/{"{"}agent-skills,prime-radiant-ai,affordabot,llm-common{"}"}`
2) Worktree-first: you are already in the task worktree for `{beads_id}`
3) Before claiming complete, run repo-appropriate validation for the files you changed
4) Open or update a draft PR after the first real commit
5) Commit with `Feature-Key: {beads_id}`

## Assignment Metadata (Required)
- MODE: initial_implementation
- BEADS_EPIC: none
- BEADS_SUBTASK: {beads_id}
- BEADS_DEPENDENCIES: {dependencies}
- FEATURE_KEY: {beads_id}
- TARGET_REPO: {repo}

## Objective
Implement the Beads task below fully enough to hand off for review without requiring the orchestrator to reconstruct your intent from logs.

## Beads Task
- Title: {title}
- Description:
{description}

## Required Execution Plan
Before substantial edits, inspect the relevant code and decide:
1. The exact files/modules you need to change
2. The smallest validation commands that prove the task is done
3. Whether an existing PR/branch for this task already exists

## Required Deliverables
1. Code changes committed and pushed
2. Draft PR created or updated
3. Validation run and summarized
4. Final response MUST end with a tech-lead-handoff compatible implementation return:

## Tech Lead Review (Implementation Return)
- MODE: implementation_return
- PR_URL: https://github.com/<org>/<repo>/pull/<n>
- PR_HEAD_SHA: <40-char sha>
- BEADS_EPIC: none
- BEADS_SUBTASK: {beads_id}
- BEADS_DEPENDENCIES: {dependencies}

### Validation
- <command>: PASS|FAIL

### Changed Files Summary
- <repo-relative path>: <what changed>

### Risks / Blockers
- None

### Decisions Needed
- None

### How To Review
1. <first review step>
2. <second review step>

## Done Gate
Do not claim complete until:
- code is committed and pushed
- a draft PR exists
- the final response includes the implementation return block above
- `PR_URL` and `PR_HEAD_SHA` are concrete, not placeholders
"""

    def _generate_review_prompt(
        self, beads_id: str, pr_url: str, pr_head_sha: str
    ) -> str:
        """Generate reviewer prompt from implementation return + review contract."""
        task = self.beads_manager.tasks.get(beads_id)
        title = task.title if task else beads_id
        description = (
            task.description or "No additional description provided."
        ).strip()
        implementation_return = self.pr_enforcer.get_implementation_return(beads_id)
        handoff_block = (
            implementation_return.raw_text
            if implementation_return and implementation_return.raw_text
            else "No implementation return captured."
        )

        return f"""you're a strict reviewer inside dx-loop:

Use [$dx-loop-review-contract](/Users/fengning/agent-skills/extended/dx-loop-review-contract/SKILL.md) as your review contract.
This review prompt follows the structure of [$prompt-writing](/Users/fengning/agent-skills/extended/prompt-writing/SKILL.md) and consumes the implementer's [$tech-lead-handoff](/Users/fengning/agent-skills/core/tech-lead-handoff/SKILL.md) return.

## Assignment Metadata
- MODE: review_fix_redispatch
- BEADS_SUBTASK: {beads_id}
- PR_URL: {pr_url}
- PR_HEAD_SHA: {pr_head_sha}

## Task Under Review
- Title: {title}
- Description:
{description}

## Implementer Return
{handoff_block}

## Review Requirements
1. Review the actual implementation against the Beads task and the implementer return
2. Prioritize concrete bugs, regressions, overclaims, missing validation, and contract drift
3. Use findings-first review style with file references when possible
4. End with exactly one verdict line in one of these forms:
   - `APPROVED: <reason>`
   - `REVISION_REQUIRED: <findings summary>`
   - `BLOCKED: <critical issue>`

## Done Gate
Do not return a verdict until you have checked whether:
- the implementation matches the Beads task scope
- the PR/handoff claims are actually supported by the diff
- validation is sufficient for the claimed outcome
"""

    def _resolve_prompt(self, beads_id: str, phase: str, worktree: Path) -> str:
        """
        Prefer repo-local prompt artifacts when present, otherwise generate one.
        """
        candidates = [
            worktree / ".dx-loop" / "prompts" / f"{beads_id}.{phase}.prompt.md",
            worktree / ".dx-loop" / "prompts" / f"{beads_id}.{phase}.md",
            worktree / "docs" / "dx-loop" / f"{beads_id}.{phase}.prompt.md",
        ]
        for candidate in candidates:
            if candidate.exists():
                return candidate.read_text()

        if phase == "review":
            baton_state = self.baton_manager.get_state(beads_id)
            pr_url = baton_state.pr_url if baton_state else ""
            pr_head_sha = baton_state.pr_head_sha if baton_state else ""
            return self._generate_review_prompt(beads_id, pr_url, pr_head_sha)
        return self._generate_implement_prompt(beads_id)

    def _set_wave_status(
        self,
        state: LoopState,
        blocker_code: Optional[BlockerCode],
        reason: str,
        blocked_details: Optional[List[Dict[str, Any]]] = None,
        dispatchable_tasks: Optional[List[str]] = None,
    ) -> None:
        """Update operator-facing wave summary and tracker state."""
        metadata = {
            "blocked_details": blocked_details or [],
            "dispatchable_tasks": dispatchable_tasks or [],
        }
        self.state_machine.transition(
            state,
            blocker_code=blocker_code,
            reason=reason,
            metadata=metadata,
            force=True,
        )
        self.wave_status = {
            "state": state.value,
            "blocker_code": blocker_code.value if blocker_code else None,
            "reason": reason,
            "blocked_details": blocked_details or [],
            "dispatchable_tasks": dispatchable_tasks or [],
        }

    def _save_state(self):
        """
        Save loop state to file - SYMMETRIC with load (P1 fix)

        Saves ALL components:
        - State machine state
        - Baton manager state
        - Beads manager state
        - Scheduler state
        - PR enforcer state
        - Notification manager state
        """
        self.wave_dir.mkdir(parents=True, exist_ok=True)

        state = {
            "wave_id": self.wave_id,
            "config": self.config,
            "version": VERSION,
            "updated_at": now_utc(),
            # State machine
            "state_machine": self.state_machine.tracker.to_dict(),
            # Baton manager
            "baton_states": {
                bid: state.to_dict()
                for bid, state in self.baton_manager.baton_states.items()
            },
            # Beads manager
            "beads_manager": self.beads_manager.to_dict(),
            # Scheduler state
            "scheduler_state": self.scheduler.state.to_dict(),
            # PR artifacts
            "pr_contract": self.pr_enforcer.to_dict(),
            # P1: Blocker classifier state for restart
            "blocker_classifier": self.blocker_classifier.to_dict(),
            # P1: Notification manager state for restart
            "notification_manager": self.notification_manager.to_dict(),
            # Operator-facing wave summary
            "wave_status": self.wave_status,
        }

        tmp_file = self.state_file.with_suffix(".tmp")
        tmp_file.write_text(json.dumps(state, indent=2))
        tmp_file.rename(self.state_file)

    def _load_state(self) -> bool:
        """
        Load loop state from file - SYMMETRIC with save (P1 fix)

        Restores ALL components for unattended restart/resume.
        """
        if not self.state_file.exists():
            return False

        try:
            state = json.loads(self.state_file.read_text())

            # Restore state machine
            if "state_machine" in state:
                self.state_machine.tracker = LoopStateTracker.from_dict(
                    state["state_machine"]
                )

            # Restore baton states
            if "baton_states" in state:
                for bid, bs_dict in state["baton_states"].items():
                    self.baton_manager.baton_states[bid] = BatonState.from_dict(bs_dict)

            # Restore beads manager
            if "beads_manager" in state:
                self.beads_manager = BeadsWaveManager.from_dict(state["beads_manager"])

            # Restore scheduler state
            if "scheduler_state" in state:
                self.scheduler.state = SchedulerState.from_dict(
                    state["scheduler_state"]
                )

            # Restore PR artifacts / handoffs
            if "pr_contract" in state:
                self.pr_enforcer = PRContractEnforcer.from_dict(state["pr_contract"])
            elif "pr_artifacts" in state:
                for bid, art_dict in state["pr_artifacts"].items():
                    self.pr_enforcer.artifacts[bid] = PRArtifact(
                        pr_url=art_dict["pr_url"], pr_head_sha=art_dict["pr_head_sha"]
                    )

            # P1: Restore blocker classifier state
            if "blocker_classifier" in state:
                self.blocker_classifier = BlockerClassifier.from_dict(
                    state["blocker_classifier"]
                )

            # P1: Restore notification manager state
            if "notification_manager" in state:
                self.notification_manager = NotificationManager.from_dict(
                    state["notification_manager"]
                )

            if "wave_status" in state:
                self.wave_status = state["wave_status"]

            return True

        except (json.JSONDecodeError, KeyError, TypeError) as e:
            print(f"ERROR: Failed to load state: {e}", file=sys.stderr)
            return False


def cmd_start(args):
    """Start dx-loop for an epic"""
    wave_id = args.wave_id or f"wave-{now_utc().replace(':', '-').replace('T', '-')}"
    epic_id = args.epic

    config = load_config_file(getattr(args, "config", None))
    loop = DxLoop(wave_id, config=config)

    is_restart = loop._load_state()

    if is_restart and not loop.beads_manager.tasks:
        print(
            f"Restart state for {wave_id} is missing task graph; rebuilding from {epic_id}"
        )
        if not loop.bootstrap_epic(epic_id):
            return 1
    elif not is_restart and not loop.bootstrap_epic(epic_id):
        return 1

    print(f"\nStarting dx-loop wave {wave_id} for epic {epic_id}")

    if is_restart:
        adopted = loop.adopt_running_jobs()
        if adopted:
            print(
                f"Adopted {len(adopted)} already-running job(s): {', '.join(adopted)}"
            )

    loop._save_state()
    success = loop.run_loop()

    return 0 if success else 1


def cmd_status(args):
    """Show dx-loop status"""
    wave_id = args.wave_id

    if not wave_id:
        # List all waves
        waves_dir = ARTIFACT_BASE / "waves"
        if not waves_dir.exists():
            print("No waves found")
            return 0

        waves = [d.name for d in waves_dir.iterdir() if d.is_dir()]
        if not waves:
            print("No waves found")
            return 0

        print("Waves:")
        for wid in sorted(waves):
            print(f"  {wid}")
        return 0

    # Show specific wave
    state_file = ARTIFACT_BASE / "waves" / wave_id / "loop_state.json"
    if not state_file.exists():
        print(f"Wave {wave_id} not found", file=sys.stderr)
        return 1

    try:
        state = json.loads(state_file.read_text())

        if args.json:
            print(json.dumps(state, indent=2))
        else:
            print(f"Wave: {wave_id}")
            print(f"Version: {state.get('version', 'unknown')}")
            print(f"Updated: {state.get('updated_at', 'unknown')}")

            wave_status = state.get("wave_status", {})
            print(f"State: {wave_status.get('state', 'unknown')}")
            print(f"Reason: {wave_status.get('reason', 'unknown')}")
            blocker_code = wave_status.get("blocker_code")
            if blocker_code:
                print(f"Blocker Code: {blocker_code}")

            scheduler_state = state.get("scheduler_state", {})
            print(f"Active: {len(scheduler_state.get('active_beads_ids', []))}")
            print(f"Completed: {len(scheduler_state.get('completed_beads_ids', []))}")
            print(f"Blocked: {len(scheduler_state.get('blocked_beads_ids', []))}")

            beads_state = state.get("beads_manager", {})
            print(f"Total tasks: {len(beads_state.get('tasks', {}))}")

            blocked_details = wave_status.get("blocked_details", [])
            if blocked_details:
                print("Blocked details:")
                for item in blocked_details[:5]:
                    if item.get("unmet_dependencies"):
                        deps = ", ".join(item.get("unmet_dependencies", []))
                        print(f"  {item.get('beads_id')}: {deps}")
                    else:
                        phase = item.get("phase")
                        reason_code = item.get("reason_code")
                        detail = item.get("detail")
                        line = item.get("beads_id", "unknown")
                        if phase:
                            line = f"{line} [{phase}]"
                        extras = [value for value in (reason_code, detail) if value]
                        if extras:
                            line = f"{line}: {' | '.join(extras)}"
                        print(f"  {line}")

            baton_states = state.get("baton_states", {})
            takeover_tasks = [
                bid
                for bid, bs in baton_states.items()
                if bs.get("phase") == "manual_takeover"
            ]
            if takeover_tasks:
                print(f"Manual takeover: {', '.join(takeover_tasks)}")

        return 0

    except (json.JSONDecodeError, KeyError):
        print(f"ERROR: Invalid state file for {wave_id}", file=sys.stderr)
        return 1


def cmd_takeover(args):
    """Manually take over a task from the loop (Pillar B)."""
    wave_id = args.wave_id
    beads_id = args.beads_id

    state_file = ARTIFACT_BASE / "waves" / wave_id / "loop_state.json"
    if not state_file.exists():
        print(f"Wave {wave_id} not found", file=sys.stderr)
        return 1

    state = json.loads(state_file.read_text())

    baton_states_raw = state.get("baton_states", {})
    if beads_id not in baton_states_raw:
        print(f"Task {beads_id} not found in wave {wave_id}", file=sys.stderr)
        return 1

    bs = baton_states_raw[beads_id]
    if bs.get("phase") == "manual_takeover":
        print(f"Task {beads_id} is already under manual takeover")
        return 0

    prev_phase = bs.get("phase", "implement")
    bs["phase"] = "manual_takeover"
    bs["metadata"] = bs.get("metadata", {})
    bs["metadata"]["takeover_at"] = now_utc()
    bs["metadata"]["takeover_from"] = prev_phase
    if args.note:
        bs["metadata"]["operator_note"] = args.note

    scheduler_raw = state.get("scheduler_state", {})
    active_ids = set(scheduler_raw.get("active_beads_ids", []))
    new_active = []
    for key in active_ids:
        bid, _ = (key.split(":", 1) + ["implement"])[:2]
        if bid != beads_id:
            new_active.append(key)
    scheduler_raw["active_beads_ids"] = new_active

    blocked_ids = set(scheduler_raw.get("blocked_beads_ids", []))
    blocked_ids.discard(beads_id)
    scheduler_raw["blocked_beads_ids"] = list(blocked_ids)

    state_file_tmp = state_file.with_suffix(".tmp")
    state_file_tmp.write_text(json.dumps(state, indent=2))
    state_file_tmp.rename(state_file)

    print(f"Task {beads_id} taken over from {prev_phase} phase")
    print("Use `dx-loop resume --wave-id <wave> --beads-id <id>` to return to loop")
    return 0


def cmd_resume(args):
    """Resume automation after manual takeover (Pillar B)."""
    wave_id = args.wave_id
    beads_id = args.beads_id

    state_file = ARTIFACT_BASE / "waves" / wave_id / "loop_state.json"
    if not state_file.exists():
        print(f"Wave {wave_id} not found", file=sys.stderr)
        return 1

    state = json.loads(state_file.read_text())

    baton_states_raw = state.get("baton_states", {})
    if beads_id not in baton_states_raw:
        print(f"Task {beads_id} not found in wave {wave_id}", file=sys.stderr)
        return 1

    bs = baton_states_raw[beads_id]
    if bs.get("phase") != "manual_takeover":
        print(
            f"Task {beads_id} is not under manual takeover (phase={bs.get('phase')})",
            file=sys.stderr,
        )
        return 1

    prev_phase = bs["metadata"].get("takeover_from", "implement")
    bs["phase"] = prev_phase
    bs["metadata"]["resumed_at"] = now_utc()

    scheduler_raw = state.get("scheduler_state", {})
    active_ids = set(scheduler_raw.get("active_beads_ids", []))
    new_active = []
    for key in active_ids:
        bid, _ = (key.split(":", 1) + ["implement"])[:2]
        if bid != beads_id:
            new_active.append(key)
    scheduler_raw["active_beads_ids"] = new_active

    blocked_ids = set(scheduler_raw.get("blocked_beads_ids", []))
    blocked_ids.discard(beads_id)
    scheduler_raw["blocked_beads_ids"] = list(blocked_ids)

    state_file_tmp = state_file.with_suffix(".tmp")
    state_file_tmp.write_text(json.dumps(state, indent=2))
    state_file_tmp.rename(state_file)

    print(f"Task {beads_id} resumed to {prev_phase} phase")
    return 0


def main():
    parser = argparse.ArgumentParser(description="dx-loop v1.3 orchestration")
    parser.add_argument("--version", action="version", version=f"dx-loop {VERSION}")

    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # start
    start_parser = subparsers.add_parser("start", help="Start dx-loop for an epic")
    start_parser.add_argument("--epic", required=True, help="Beads epic ID")
    start_parser.add_argument(
        "--wave-id", help="Wave ID (auto-generated if not provided)"
    )
    start_parser.add_argument("--config", help="Path to config file")
    start_parser.set_defaults(func=cmd_start)

    # status
    status_parser = subparsers.add_parser("status", help="Show dx-loop status")
    status_parser.add_argument("--wave-id", help="Wave ID")
    status_parser.add_argument("--json", action="store_true", help="JSON output")
    status_parser.set_defaults(func=cmd_status)

    # takeover (Pillar B)
    takeover_parser = subparsers.add_parser(
        "takeover", help="Manually take over a task"
    )
    takeover_parser.add_argument("--wave-id", required=True, help="Wave ID")
    takeover_parser.add_argument("--beads-id", required=True, help="Beads task ID")
    takeover_parser.add_argument("--note", help="Optional operator note")
    takeover_parser.set_defaults(func=cmd_takeover)

    # resume (Pillar B)
    resume_parser = subparsers.add_parser(
        "resume", help="Resume automation after takeover"
    )
    resume_parser.add_argument("--wave-id", required=True, help="Wave ID")
    resume_parser.add_argument("--beads-id", required=True, help="Beads task ID")
    resume_parser.set_defaults(func=cmd_resume)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
