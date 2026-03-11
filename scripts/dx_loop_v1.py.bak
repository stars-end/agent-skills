#!/usr/bin/env python3
"""
dx-loop v1 - PR-aware orchestration surface over dx-runner substrate

Reuses Ralph concepts (baton, topological deps, checkpoint/resume) while replacing
the control plane with governed dx-runner dispatch and enforcing PR artifact contracts.

Usage:
    dx-loop start --epic <epic-id> [--config <path>]
    dx-loop status [--wave-id <id>] [--json]
    dx-loop check --wave-id <id> [--json]
    dx-loop report --wave-id <id> [--format json|markdown]
"""

from __future__ import annotations
import argparse, json, os, subprocess, sys, time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Dict, Any, List

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent / "lib"))

from dx_loop import (
    LoopState, BlockerCode, LoopStateMachine, LoopStateTracker,
    BatonPhase, BatonManager, ReviewVerdict,
    BlockerClassifier, BlockerState,
    PRContractEnforcer, PRArtifact,
    BeadsWaveManager,
    NotificationManager,
)

VERSION = "1.0.0"
ARTIFACT_BASE = Path("/tmp/dx-loop")
DEFAULT_CONFIG = {
    "max_attempts": 3,
    "max_revisions": 3,
    "max_parallel": 2,
    "cadence_seconds": 600,  # 10 minutes
    "provider": "opencode",
    "require_review": True,
}


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class DxLoop:
    """
    Main dx-loop orchestration class
    
    Integrates:
    - dx-runner substrate for execution
    - Baton manager for implement/review cycle
    - State machine with blocker taxonomy
    - PR contract enforcer
    - Beads wave manager
    - Notification manager
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
        
        # Artifact paths
        self.wave_dir = ARTIFACT_BASE / "waves" / wave_id
        self.state_file = self.wave_dir / "loop_state.json"
        self.log_dir = self.wave_dir / "logs"
        self.outcome_dir = self.wave_dir / "outcomes"
    
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
        Run main loop cycle
        
        Monitors active tasks, checks progress via dx-runner,
        classifies blockers, and advances wave.
        """
        iteration = 0
        
        while iteration < max_iterations:
            iteration += 1
            
            # Get next wave of ready tasks
            ready = self.beads_manager.get_next_wave()
            if not ready:
                if not self.beads_manager.has_pending_tasks():
                    print("Wave complete - no pending tasks")
                    return True
                print("No ready tasks, waiting...")
                time.sleep(self.config["cadence_seconds"])
                continue
            
            # Dispatch ready tasks
            for beads_id in ready:
                self._dispatch_task(beads_id)
            
            # Check progress of active tasks
            self._check_progress()
            
            # Sleep until next cycle
            time.sleep(self.config["cadence_seconds"])
        
        return False
    
    def _dispatch_task(self, beads_id: str) -> bool:
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
            return True
        else:
            print(f"Task {beads_id} blocked: {next_action}")
            return False
    
    def _start_implement(self, beads_id: str) -> bool:
        """Start implement phase via dx-runner"""
        # Generate prompt
        prompt = self._generate_implement_prompt(beads_id)
        prompt_file = ARTIFACT_BASE / "prompts" / f"{beads_id}.implement.prompt"
        prompt_file.parent.mkdir(parents=True, exist_ok=True)
        prompt_file.write_text(prompt)
        
        # Start dx-runner
        run_id = f"{beads_id}-{now_utc().replace(':', '-').replace('T', '-')}"
        cmd = [
            "dx-runner", "start",
            "--beads", beads_id,
            "--provider", self.config["provider"],
            "--prompt-file", str(prompt_file),
        ]
        
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
            # Track baton state
            self.baton_manager.start_implement(beads_id, run_id=run_id)
            
            print(f"Started implement for {beads_id} (run_id={run_id}, pid={proc.pid})")
            return True
        
        except Exception as e:
            print(f"ERROR: Failed to start implement for {beads_id}: {e}", file=sys.stderr)
            return False
    
    def _start_review(self, beads_id: str) -> bool:
        """Start review phase via dx-runner"""
        # Get implement artifacts
        baton_state = self.baton_manager.get_state(beads_id)
        if not baton_state or not baton_state.pr_url:
            print(f"ERROR: No PR artifact for {beads_id}, cannot review", file=sys.stderr)
            return False
        
        # Generate review prompt
        prompt = self._generate_review_prompt(beads_id, baton_state.pr_url, baton_state.pr_head_sha)
        prompt_file = ARTIFACT_BASE / "prompts" / f"{beads_id}.review.prompt"
        prompt_file.parent.mkdir(parents=True, exist_ok=True)
        prompt_file.write_text(prompt)
        
        # Start dx-runner
        review_beads_id = f"{beads_id}-review"
        run_id = f"{review_beads_id}-{now_utc().replace(':', '-').replace('T', '-')}"
        cmd = [
            "dx-runner", "start",
            "--beads", review_beads_id,
            "--provider", self.config["provider"],
            "--prompt-file", str(prompt_file),
        ]
        
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
            # Track baton state
            self.baton_manager.start_review(beads_id, run_id=run_id)
            
            print(f"Started review for {beads_id} (run_id={run_id}, pid={proc.pid})")
            return True
        
        except Exception as e:
            print(f"ERROR: Failed to start review for {beads_id}: {e}", file=sys.stderr)
            return False
    
    def _check_progress(self):
        """Check progress of all active tasks via dx-runner"""
        for beads_id, baton_state in self.baton_manager.baton_states.items():
            if baton_state.phase in (BatonPhase.COMPLETE, BatonPhase.FAILED):
                continue
            
            if baton_state.phase == BatonPhase.IMPLEMENT:
                self._check_implement_progress(beads_id)
            elif baton_state.phase == BatonPhase.REVIEW:
                self._check_review_progress(beads_id)
    
    def _check_implement_progress(self, beads_id: str):
        """Check implement phase progress"""
        try:
            result = subprocess.run(
                ["dx-runner", "check", "--beads", beads_id, "--json"],
                capture_output=True,
                text=True,
                timeout=30,
            )
            
            if not result.stdout.strip():
                return
            
            data = json.loads(result.stdout)
            state = data.get("state", "unknown")
            
            # Check for completion
            if state in ("exited_ok", "exited_err"):
                # Extract PR artifacts from output
                log_content = self._read_runner_log(beads_id)
                artifact = self.pr_enforcer.extract_from_agent_output(log_content)
                
                if artifact and artifact.is_valid():
                    # Register artifact and transition to review
                    self.pr_enforcer.register_artifact(
                        beads_id, artifact.pr_url, artifact.pr_head_sha
                    )
                    
                    if self.config["require_review"]:
                        self.baton_manager.complete_implement(
                            beads_id,
                            pr_url=artifact.pr_url,
                            pr_head_sha=artifact.pr_head_sha,
                        )
                        print(f"Implement complete for {beads_id}, transitioning to review")
                    else:
                        self.baton_manager.baton_states[beads_id].phase = BatonPhase.COMPLETE
                        self.beads_manager.mark_completed(beads_id)
                        print(f"Implement complete for {beads_id} (no review required)")
                else:
                    # Classify blocker
                    blocker = self.blocker_classifier.classify(
                        data.get("reason_code"),
                        beads_id=beads_id,
                        wave_id=self.wave_id,
                        has_pr_artifacts=False,
                    )
                    
                    # Emit notification if needed
                    notification = self.notification_manager.create_notification(blocker)
                    if notification:
                        print(notification.format_cli())
        
        except (subprocess.TimeoutExpired, json.JSONDecodeError, Exception):
            pass
    
    def _check_review_progress(self, beads_id: str):
        """Check review phase progress"""
        review_beads_id = f"{beads_id}-review"
        
        try:
            result = subprocess.run(
                ["dx-runner", "check", "--beads", review_beads_id, "--json"],
                capture_output=True,
                text=True,
                timeout=30,
            )
            
            if not result.stdout.strip():
                return
            
            data = json.loads(result.stdout)
            state = data.get("state", "unknown")
            
            if state in ("exited_ok", "exited_err"):
                # Parse review verdict
                log_content = self._read_runner_log(review_beads_id)
                verdict = self._parse_review_verdict(log_content)
                
                if verdict:
                    baton_state = self.baton_manager.complete_review(
                        beads_id,
                        verdict,
                        pr_url=self.pr_enforcer.get_artifact(beads_id).pr_url if self.pr_enforcer.get_artifact(beads_id) else None,
                        pr_head_sha=self.pr_enforcer.get_artifact(beads_id).pr_head_sha if self.pr_enforcer.get_artifact(beads_id) else None,
                    )
                    
                    if baton_state.phase == BatonPhase.COMPLETE:
                        self.beads_manager.mark_completed(beads_id)
                        print(f"Review APPROVED for {beads_id}, task complete")
                        
                        # Emit merge_ready notification
                        blocker = self.blocker_classifier.classify(
                            None,
                            beads_id=beads_id,
                            wave_id=self.wave_id,
                            has_pr_artifacts=True,
                            checks_passing=True,
                        )
                        notification = self.notification_manager.create_notification(blocker)
                        if notification:
                            print(notification.format_cli())
                    else:
                        print(f"Review verdict for {beads_id}: {verdict.value}")
        
        except (subprocess.TimeoutExpired, json.JSONDecodeError, Exception):
            pass
    
    def _read_runner_log(self, beads_id: str) -> str:
        """Read dx-runner log for a beads ID"""
        log_path = Path(f"/tmp/dx-runner/{self.config['provider']}/{beads_id}.log")
        if not log_path.exists():
            return ""
        try:
            return log_path.read_text()
        except OSError:
            return ""
    
    def _parse_review_verdict(self, log_content: str) -> Optional[ReviewVerdict]:
        """Parse review verdict from log content"""
        for line in reversed(log_content.split('\n')):
            line = line.strip()
            if "APPROVED" in line.upper():
                return ReviewVerdict.APPROVED
            elif "REVISION_REQUIRED" in line.upper():
                return ReviewVerdict.REVISION_REQUIRED
            elif "BLOCKED" in line.upper():
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
    
    def _generate_review_prompt(self, beads_id: str, pr_url: str, pr_head_sha: str) -> str:
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
    
    def _save_state(self):
        """Save loop state to file"""
        self.wave_dir.mkdir(parents=True, exist_ok=True)
        
        state = {
            "wave_id": self.wave_id,
            "config": self.config,
            "state_machine": self.state_machine.tracker.to_dict(),
            "beads_manager": self.beads_manager.to_dict(),
            "baton_states": {
                bid: state.to_dict()
                for bid, state in self.baton_manager.baton_states.items()
            },
            "updated_at": now_utc(),
        }
        
        tmp_file = self.state_file.with_suffix(".tmp")
        tmp_file.write_text(json.dumps(state, indent=2))
        tmp_file.rename(self.state_file)
    
    def _load_state(self) -> bool:
        """Load loop state from file"""
        if not self.state_file.exists():
            return False
        
        try:
            state = json.loads(self.state_file.read_text())
            
            if "state_machine" in state:
                self.state_machine.tracker = LoopStateTracker.from_dict(state["state_machine"])
            
            if "baton_states" in state:
                for bid, baton_data in state["baton_states"].items():
                    from dx_loop.baton import BatonState
                    self.baton_manager.baton_states[bid] = BatonState.from_dict(baton_data)
            
            return True
        
        except (json.JSONDecodeError, KeyError):
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
            print(f"Updated: {state.get('updated_at', 'unknown')}")
            print(f"Tasks: {len(state.get('beads_manager', {}).get('tasks', {}))}")
            print(f"Completed: {len(state.get('beads_manager', {}).get('completed', []))}")
        
        return 0
    
    except (json.JSONDecodeError, KeyError):
        print(f"ERROR: Invalid state file for {wave_id}", file=sys.stderr)
        return 1


def main():
    parser = argparse.ArgumentParser(description="dx-loop v1 orchestration")
    parser.add_argument("--version", action="version", version=f"dx-loop {VERSION}")
    
    subparsers = parser.add_subparsers(dest="command", help="Commands")
    
    # start
    start_parser = subparsers.add_parser("start", help="Start dx-loop for an epic")
    start_parser.add_argument("--epic", required=True, help="Beads epic ID")
    start_parser.add_argument("--wave-id", help="Wave ID (auto-generated if not provided)")
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
