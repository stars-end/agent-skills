"""
Skill Optimizer Wrapper for GEPA.

Wraps GEPA optimize_anything to evolve skills for coding agents.
"""

from pathlib import Path
from dataclasses import dataclass
import sys
import json

# Add GEPA to path
gepa_path = Path.home() / "gepa" / "src"
if str(gepa_path) not in sys.path:
    sys.path.insert(0, str(gepa_path))

from gepa.optimize_anything import (
    optimize_anything,
    GEPAConfig,
    EngineConfig,
    ReflectionConfig
)

from extended.gskill.lib.opencode_adapter import make_opencode_lm
from extended.gskill.lib.evaluator import make_gepa_evaluator


@dataclass
class SkillOptimizationResult:
    """Result of skill optimization."""
    best_skill: str
    best_score: float
    num_candidates: int
    all_candidates: list[str]


class SkillOptimizer:
    """
    Wrap GEPA optimize_anything to evolve skills for coding agents.

    CRITICAL:
    - Uses 'current_candidate' key for string candidates
    - Wires custom reflection template from templates/reflection_prompt.md
    """

    def __init__(
        self,
        repo_path: Path,
        reflection_model: str = "zhipuai-coding-plan/glm-5",
        max_metric_calls: int = 100,
        reflection_template_path: Path | None = None,
    ):
        self.repo_path = Path(repo_path)
        self.reflection_model = reflection_model
        self.max_metric_calls = max_metric_calls
        self.reflection_template_path = reflection_template_path or \
            Path(__file__).parent.parent / "templates" / "reflection_prompt.md"

    def optimize(
        self,
        tasks_path: Path,
        seed_skill: str = "",
        objective: str = "Help coding agent fix bugs in this repository",
    ) -> SkillOptimizationResult:
        """
        Run GEPA optimization loop to evolve skills.
        """
        tasks = self._load_tasks(tasks_path)
        evaluator = make_gepa_evaluator(self.repo_path)
        reflection_lm = make_opencode_lm(self.reflection_model)

        # CRITICAL: Load custom reflection template
        reflection_template = self._load_reflection_template()

        result = optimize_anything(
            seed_candidate=seed_skill,
            evaluator=evaluator,
            dataset=tasks,
            objective=objective,
            config=GEPAConfig(
                engine=EngineConfig(
                    max_metric_calls=self.max_metric_calls,
                ),
                reflection=ReflectionConfig(
                    reflection_lm=reflection_lm,
                    reflection_prompt_template=reflection_template,  # WIRED
                ),
            ),
        )

        best_score = result.val_aggregate_scores[result.best_idx]

        # CRITICAL: Extract candidates using CORRECT key
        # String candidates use 'current_candidate' key, NOT 'skill'
        all_candidates = []
        for cand in result.candidates:
            if isinstance(cand, dict):
                # Use correct key for string candidates
                all_candidates.append(cand.get("current_candidate", cand.get("skill", "")))
            else:
                all_candidates.append(str(cand))

        return SkillOptimizationResult(
            best_skill=result.best_candidate,
            best_score=best_score,
            num_candidates=result.num_candidates,
            all_candidates=all_candidates,
        )

    def _load_tasks(self, path: Path) -> list[dict]:
        """Load tasks from JSONL as list of dicts."""
        tasks = []
        with open(path) as f:
            for line in f:
                if line.strip():
                    tasks.append(json.loads(line))
        return tasks

    def _load_reflection_template(self) -> str:
        """Load custom reflection template from file."""
        if self.reflection_template_path.exists():
            return self.reflection_template_path.read_text()
        else:
            # Return default template if file not found
            return """I am optimizing a skill file that helps coding agents work effectively in a repository. The current skill is:
<curr_param>

Below is evaluation data showing how this skill performed:
<side_info>

Your task is to propose an improved skill that will help the agent succeed on more tasks."""


def run_skill_evolution(
    repo_name: str,
    repo_path: Path,
    tasks_path: Path,
    output_path: Path,
    max_metric_calls: int = 100,
) -> Path:
    """
    Full pipeline: evolve skill and save to output path.

    Returns path to learned SKILL.md
    """
    optimizer = SkillOptimizer(repo_path, max_metric_calls=max_metric_calls)

    # Load seed skill
    seed_path = Path(__file__).parent.parent / "templates" / "skill_seed.md"
    seed_skill = seed_path.read_text() if seed_path.exists() else ""

    result = optimizer.optimize(tasks_path, seed_skill=seed_skill)

    # Write learned skill
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(result.best_skill)

    print(f"Evolved skill (score: {result.best_score:.2f})")
    print(f"Candidates explored: {result.num_candidates}")

    return output_path
