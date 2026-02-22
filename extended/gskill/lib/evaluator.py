"""
Agent Evaluation Harness for GEPA.

Runs opencode with a skill on a task and returns (score, side_info) for GEPA.
CRITICAL: Evaluation runs on MUTATED task state, not original.
"""

import subprocess
import tempfile
import shutil
from pathlib import Path
from dataclasses import dataclass
from typing import Any


@dataclass
class EvaluationResult:
    """Result of evaluating an agent on a task."""
    score: float  # 0.0 to 1.0
    passed: bool
    test_output: str
    agent_trace: str
    error_message: str | None = None


class SkillEvaluator:
    """
    Evaluate agent performance on bug-fix tasks.

    CRITICAL: Runs on MUTATED task state, not original.
    """

    def __init__(self, repo_path: Path, timeout: int = 300):
        self.repo_path = Path(repo_path)
        self.timeout = timeout

    def evaluate(self, skill_md: str, task: dict[str, Any]) -> tuple[float, str]:
        """
        Run agent with skill on task, return (score, side_info).

        GEPA calls this as: evaluator(candidate, example=task)
        where candidate=skill_md, example=task dict.

        CRITICAL: Runs on MUTATED task state, not original.
        """
        target_file = task.get("target_file", "unknown")
        description = task.get("description", "unknown task")
        test_command = task.get("test_command", "")
        mutation_patch = task.get("mutation_patch", "")
        mutated_code = task.get("mutated_code", "")

        # Create isolated evaluation environment
        with tempfile.TemporaryDirectory() as tmpdir:
            eval_repo = Path(tmpdir) / "repo"
            shutil.copytree(self.repo_path, eval_repo)

            # STEP 1: Apply task mutation BEFORE agent run
            # CRITICAL: Must have either patch or mutated_code - no original_code fallback
            if mutation_patch:
                applied = self._apply_patch(eval_repo, mutation_patch, target_file)
                if not applied:
                    return (0.0, f"Failed to apply mutation patch for {target_file}")
            elif mutated_code:
                # Direct code replacement from mutated_code field
                target_path = eval_repo / target_file
                target_path.write_text(mutated_code)
            else:
                # CRITICAL: Fail fast if no mutation available
                return (0.0, f"No mutation data for task {task.get('id', 'unknown')} - cannot evaluate")

            # STEP 2: Build agent prompt
            prompt = self._build_prompt(description, target_file, skill_md)

            try:
                # STEP 3: Run opencode on MUTATED code
                result = subprocess.run(
                    [
                        "opencode", "run",
                        "-m", "zhipuai-coding-plan/glm-5",
                        "--format", "default",
                        "--dir", str(eval_repo),
                        prompt
                    ],
                    capture_output=True,
                    text=True,
                    timeout=self.timeout
                )

                agent_trace = result.stdout

                # STEP 4: Run test against agent's modified code
                test_result = subprocess.run(
                    test_command,
                    shell=True,
                    cwd=str(eval_repo),
                    capture_output=True,
                    text=True,
                    timeout=60
                )

                passed = test_result.returncode == 0
                score = 1.0 if passed else 0.0

                # Build side_info for reflection
                side_info = self._build_side_info(
                    task_id=task.get("id", "unknown"),
                    description=description,
                    target_file=target_file,
                    agent_trace=agent_trace,
                    test_output=test_result.stdout + test_result.stderr,
                    passed=passed
                )

                return (score, side_info)

            except subprocess.TimeoutExpired:
                return (0.0, f"Evaluation timed out after {self.timeout}s")
            except Exception as e:
                return (0.0, f"Evaluation error: {str(e)}")

    def _apply_patch(self, repo_path: Path, patch: str, target_file: str) -> bool:
        """
        Apply mutation patch to isolated repo.

        CRITICAL: Patch has a/ b/ prefixes (from generator), applied with -p1.
        Returns True if successful, False otherwise.
        """
        patch_path = repo_path / ".mutation.patch"
        patch_path.write_text(patch)

        result = subprocess.run(
            ["patch", "-p1", "-i", str(patch_path)],
            cwd=str(repo_path),
            capture_output=True
        )
        patch_path.unlink()

        return result.returncode == 0

    def _build_prompt(self, description: str, target_file: str, skill_md: str) -> str:
        """Build prompt for agent with skill context."""
        return f"""You are a software engineer fixing a bug.

## Task
{description}

## Target File
{target_file}

## Skills (follow these patterns)
{skill_md}

## Instructions
1. Read the target file
2. Identify the bug
3. Fix it
4. Do NOT run tests (they will be run separately)

Begin by reading the file."""

    def _build_side_info(
        self,
        task_id: str,
        description: str,
        target_file: str,
        agent_trace: str,
        test_output: str,
        passed: bool
    ) -> str:
        """Build diagnostic info for reflection LLM."""
        return f"""## Task ID: {task_id}
## Description: {description}
## Target: {target_file}
## Result: {'PASSED' if passed else 'FAILED'}

## Agent Trace (last 2000 chars)
{agent_trace[-2000:]}

## Test Output
{test_output[-2000:]}
"""


def make_gepa_evaluator(repo_path: Path) -> callable:
    """
    Create evaluator compatible with GEPA's expected signature.
    GEPA calls: evaluator(candidate, example=task, **kwargs)
    """
    evaluator = SkillEvaluator(repo_path)

    def gepa_evaluator(candidate: str, example: dict = None, **kwargs) -> tuple[float, str]:
        task = example or {}
        return evaluator.evaluate(candidate, task)

    return gepa_evaluator
