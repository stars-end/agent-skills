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
from dx_loop.runner_adapter import RunnerAdapter, RunnerTaskState

VERSION = "1.1.0"
ARTIFACT_BASE = Path("/tmp/dx-loop")
DEFAULT_CONFIG = {
    "max_attempts": 3,
    "max_revisions": 3,
    "max_parallel": 2,
    "cadence_seconds": 600,  # 10 minutes
    "provider": "opencode",
    "require_review": True,
    "worktree_base": "/tmp/agents",  # Base dir for worktrees
}


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
        self.runner_adapter = RunnerAdapter(provider=self.config["provider"])

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
                    self._set_wave_status(
                        LoopState.WAITING_ON_DEPENDENCY,
                        BlockerCode.WAITING_ON_DEPENDENCY,
                        f"No dispatches: waiting on dependencies for {len(blocked_ids)} task(s)",
                        blocked_details=readiness.waiting_on_dependencies,
                    )
                    print(
                        f"No ready tasks: waiting on dependencies for {len(blocked_ids)} task(s)"
                    )
                    for item in readiness.waiting_on_dependencies[:3]:
                        deps = ", ".join(item["unmet_dependencies"])
                        print(f"  {item['beads_id']} waiting on: {deps}")
                else:
                    self._set_wave_status(
                        LoopState.PENDING,
                        None,
                        "No ready tasks, waiting for next cadence",
                    )
                    print("No ready tasks, waiting for next cadence...")
            else:
                self.scheduler.state.blocked_beads_ids.clear()
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
                        if not self.scheduler.state.is_completed(tid):
                            dispatchable.append((tid, expected_phase))

                if dispatchable:
                    dispatchable_ids = [tid for tid, _ in dispatchable]
                    self._set_wave_status(
                        LoopState.IN_PROGRESS_HEALTHY,
                        None,
                        f"Dispatching {len(dispatchable_ids)} task(s)",
                        dispatchable_tasks=dispatchable_ids,
                    )
                    print(f"Dispatching {len(dispatchable)} task(s)")
                    for beads_id, phase in dispatchable:
                        if self._dispatch_task(beads_id, phase):
                            self.scheduler.state.mark_dispatched(beads_id, phase)
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

    def _dispatch_task(self, beads_id: str, phase: str = "implement") -> bool:
        """Dispatch a single task through implement/review cycle"""
        # Check baton phase
        baton_state = self.baton_manager.get_state(beads_id)
        next_action = self.baton_manager.get_next_action(beads_id)

        if next_action == "start_implement":
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
        Falls back to beads_id as repo name if task has no repo info.
        """
        task = self.beads_manager.tasks.get(beads_id)
        repo = "agent-skills"  # Default repo

        # Try to extract repo from task metadata if available
        if task and hasattr(task, "metadata") and task.metadata:
            repo = task.metadata.get("repo", repo)

        worktree_base = Path(self.config.get("worktree_base", "/tmp/agents"))
        return worktree_base / beads_id / repo

    def _start_implement(self, beads_id: str) -> bool:
        """Start implement phase via RunnerAdapter (P0 fix: explicit worktree)"""
        # Generate prompt
        prompt = self._generate_implement_prompt(beads_id)
        prompt_file = ARTIFACT_BASE / "prompts" / f"{beads_id}.implement.prompt"
        prompt_file.parent.mkdir(parents=True, exist_ok=True)
        prompt_file.write_text(prompt)

        # Compute worktree path (P0 fix)
        worktree = self._get_worktree_path(beads_id)

        # Use RunnerAdapter with explicit worktree (governed dispatch)
        run_id = f"{beads_id}-{now_utc().replace(':', '-').replace('T', '-')}"

        if self.runner_adapter.start(beads_id, prompt_file, worktree=worktree):
            # Track baton state
            self.baton_manager.start_implement(beads_id, run_id=run_id)
            print(f"Started implement for {beads_id} (run_id={run_id})")
            return True
        else:
            print(f"ERROR: Failed to start implement for {beads_id}", file=sys.stderr)
            return False

    def _start_review(self, beads_id: str) -> bool:
        """Start review phase via RunnerAdapter (P0 fix: explicit worktree)"""
        # Get implement artifacts
        baton_state = self.baton_manager.get_state(beads_id)
        if not baton_state or not baton_state.pr_url:
            print(
                f"ERROR: No PR artifact for {beads_id}, cannot review", file=sys.stderr
            )
            return False

        # Generate review prompt
        prompt = self._generate_review_prompt(
            beads_id, baton_state.pr_url, baton_state.pr_head_sha
        )
        prompt_file = ARTIFACT_BASE / "prompts" / f"{beads_id}.review.prompt"
        prompt_file.parent.mkdir(parents=True, exist_ok=True)
        prompt_file.write_text(prompt)

        # P0 FIX: Use explicit worktree (same as implement, review happens on same codebase)
        worktree = self._get_worktree_path(beads_id)

        # Start via RunnerAdapter with explicit worktree
        review_beads_id = f"{beads_id}-review"
        run_id = f"{review_beads_id}-{now_utc().replace(':', '-').replace('T', '-')}"

        if self.runner_adapter.start(review_beads_id, prompt_file, worktree=worktree):
            self.baton_manager.start_review(beads_id, run_id=run_id)
            print(f"Started review for {beads_id} (run_id={run_id})")
            return True
        else:
            print(f"ERROR: Failed to start review for {beads_id}", file=sys.stderr)
            return False

    def _check_progress(self):
        """Check progress of all active tasks via RunnerAdapter"""
        for beads_id, baton_state in list(self.baton_manager.baton_states.items()):
            if baton_state.phase in (BatonPhase.COMPLETE, BatonPhase.FAILED):
                continue

            if baton_state.phase == BatonPhase.IMPLEMENT:
                self._check_implement_progress(beads_id)
            elif baton_state.phase == BatonPhase.REVIEW:
                self._check_review_progress(beads_id)

    def _check_implement_progress(self, beads_id: str):
        """Check implement phase progress via RunnerAdapter"""
        task_state = self.runner_adapter.check(beads_id)

        if not task_state or task_state.state == "missing":
            return

        # Check for completion
        if task_state.is_complete():
            # Extract PR artifacts
            artifacts = self.runner_adapter.extract_pr_artifacts(beads_id)

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
                # Classify blocker
                blocker = self.blocker_classifier.classify(
                    task_state.reason_code,
                    beads_id=beads_id,
                    wave_id=self.wave_id,
                    has_pr_artifacts=False,
                )

                # Emit notification (P1 fix: emits on first occurrence)
                notification = self.notification_manager.create_notification(blocker)
                if notification:
                    print(notification.format_cli())

                # Mark as blocked in scheduler
                self.scheduler.state.mark_blocked(beads_id)

    def _check_review_progress(self, beads_id: str):
        """Check review phase progress"""
        review_beads_id = f"{beads_id}-review"
        task_state = self.runner_adapter.check(review_beads_id)

        if not task_state or task_state.state == "missing":
            return

        if task_state.is_complete():
            # Parse review verdict
            report = self.runner_adapter.report(review_beads_id)
            verdict = self._parse_review_verdict(report)

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
                    print(f"Review APPROVED for {beads_id}, task complete")

                    # Emit merge_ready notification
                    blocker = self.blocker_classifier.classify(
                        None,
                        beads_id=beads_id,
                        wave_id=self.wave_id,
                        has_pr_artifacts=True,
                        checks_passing=True,
                    )
                    notification = self.notification_manager.create_notification(
                        blocker
                    )
                    if notification:
                        print(notification.format_cli())
                elif baton_state.phase == BatonPhase.IMPLEMENT:
                    # P0 FIX: Clear "review" phase to allow revision implement dispatch
                    self.scheduler.state.clear_phase(beads_id, "review")
                    print(
                        f"Review REVISION_REQUIRED for {beads_id}, returning to implement"
                    )
                else:
                    print(f"Review verdict for {beads_id}: {verdict.value}")

    def _parse_review_verdict(
        self, report: Optional[Dict[str, Any]]
    ) -> Optional[ReviewVerdict]:
        """Parse review verdict from report"""
        if not report:
            return None

        # Check for explicit verdict in report
        verdict_str = report.get("verdict", "").upper()

        if "APPROVED" in verdict_str:
            return ReviewVerdict.APPROVED
        elif "REVISION_REQUIRED" in verdict_str:
            return ReviewVerdict.REVISION_REQUIRED
        elif "BLOCKED" in verdict_str:
            return ReviewVerdict.BLOCKED

        return None

    def _generate_implement_prompt(self, beads_id: str) -> str:
        """Generate implementer prompt"""
        task = self.beads_manager.tasks.get(beads_id)
        title = task.title if task else beads_id

        return f"""Implement task for Beads issue {beads_id}.

Title: {title}

Requirements:
1. Implement the task completely following repository conventions
2. Write tests if applicable
3. Create a draft PR after first real commit
4. Commit with Feature-Key: {beads_id}

REQUIRED OUTPUT (must be last line):
PR_URL: https://github.com/<org>/<repo>/pull/<number>
PR_HEAD_SHA: <40-char-sha>

Example:
PR_URL: https://github.com/example/myapp/pull/42
PR_HEAD_SHA: abc123def456789012345678901234567890abcd
"""

    def _generate_review_prompt(
        self, beads_id: str, pr_url: str, pr_head_sha: str
    ) -> str:
        """Generate reviewer prompt"""
        return f"""Review implementation for Beads issue {beads_id}.

PR: {pr_url}
Commit: {pr_head_sha}

Requirements:
1. Review the implementation for correctness
2. Verify tests pass
3. Check code follows conventions

OUTPUT (one of):
APPROVED: <reason>
REVISION_REQUIRED: <findings>
BLOCKED: <critical issues>
"""

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
            "pr_artifacts": {
                bid: {"pr_url": art.pr_url, "pr_head_sha": art.pr_head_sha}
                for bid, art in self.pr_enforcer.artifacts.items()
            },
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

            # Restore PR artifacts
            if "pr_artifacts" in state:
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

    loop = DxLoop(wave_id)

    if not loop.bootstrap_epic(epic_id):
        return 1

    print(f"\nStarting dx-loop wave {wave_id} for epic {epic_id}")
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
                print("Waiting on dependencies:")
                for item in blocked_details[:5]:
                    deps = ", ".join(item.get("unmet_dependencies", []))
                    print(f"  {item.get('beads_id')}: {deps}")

        return 0

    except (json.JSONDecodeError, KeyError):
        print(f"ERROR: Invalid state file for {wave_id}", file=sys.stderr)
        return 1


def main():
    parser = argparse.ArgumentParser(description="dx-loop v1.1 orchestration")
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

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
