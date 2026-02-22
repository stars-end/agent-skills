"""
SWE-smith Task Generator Wrapper for gskill.

Generates verified-failing bug-fix tasks using SWE-smith procedural modifiers.
Tasks are ONLY admitted when mutation causes verified failing tests.
"""

from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Generator, Any
import json
import subprocess
import tempfile
import shutil
import fnmatch


@dataclass
class Task:
    """A bug-fix task with mutation data."""
    id: str
    description: str
    repo_path: str
    target_file: str
    test_command: str
    setup_commands: list[str]
    mutation_patch: str  # The actual patch to apply
    mutated_code: str    # The mutated code (for evaluator fallback)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class TaskGenerator:
    """
    Wrap SWE-smith procedural bug generation to produce tasks for any repo.

    CRITICAL: Tasks are ONLY admitted when mutation causes verified failing tests.
    """

    def __init__(self, repo_path: Path, language: str = "python"):
        self.repo_path = Path(repo_path)
        self.language = language.lower()
        self.target_patterns: list[str] = []
        self.exclude_patterns: list[str] = []

        # Import SWE-smith modifiers
        from swesmith.bug_gen.procedural import MAP_EXT_TO_MODIFIERS

        ext_map = {
            "python": ".py",
            "typescript": ".ts",
            "javascript": ".js",
        }
        self.file_ext = ext_map.get(self.language, ".py")
        self.modifiers = MAP_EXT_TO_MODIFIERS.get(self.file_ext, [])

    def set_target_patterns(self, patterns: list[str]):
        """Set glob patterns for target files."""
        self.target_patterns = patterns

    def set_exclude_patterns(self, patterns: list[str]):
        """Set glob patterns for files to exclude."""
        self.exclude_patterns = patterns

    def discover_targets(self) -> list[Path]:
        """Find mutable code files in repo using glob matching for exclusions."""
        targets = []
        for pattern in self.target_patterns:
            for file_path in self.repo_path.glob(pattern):
                rel_path = file_path.relative_to(self.repo_path)
                excluded = False
                for exc_pattern in self.exclude_patterns:
                    if fnmatch.fnmatch(str(rel_path), exc_pattern):
                        excluded = True
                        break
                if not excluded:
                    targets.append(file_path)
        return targets

    def generate_tasks(self, max_tasks: int = 100) -> Generator[Task, None, None]:
        """Generate tasks by applying procedural modifiers."""
        targets = self.discover_targets()
        task_count = 0

        for target_file in targets:
            if task_count >= max_tasks:
                break

            for modifier in self.modifiers:
                if task_count >= max_tasks:
                    break

                # Apply REAL modifier logic and verify
                task = self._apply_modifier_and_verify(target_file, modifier)
                if task:
                    yield task
                    task_count += 1

    def _apply_modifier_and_verify(self, target_file: Path, modifier) -> Task | None:
        """
        Apply modifier, verify test fails, return task only if verified.

        CRITICAL: Tasks are ONLY admitted when mutation causes verified failing tests.
        """
        # Discover code entities using adapter-based extraction
        entities = self._discover_entities(target_file)

        for entity in entities:
            # Apply ACTUAL modifier logic
            # modifier.modify() returns BugRewrite object, NOT plain code
            try:
                bug_rewrite = modifier.modify(entity)
            except Exception:
                continue

            # CRITICAL: Extract mutated code from BugRewrite.rewrite field
            if not bug_rewrite or not hasattr(bug_rewrite, 'rewrite'):
                continue

            mutated_code = bug_rewrite.rewrite
            if not mutated_code:
                continue

            original_code = target_file.read_text()

            # Generate patch with a/ b/ prefixes for -p1 compatibility
            patch = self._create_patch(target_file, original_code, mutated_code)

            # Find real test file
            test_file = self._find_test_file(target_file)
            if not test_file:
                continue  # NO fallback - skip if no test exists

            test_command = self._build_test_command(test_file, entity.name)

            # VERIFY: Run test against mutated code
            with tempfile.TemporaryDirectory() as tmpdir:
                tmp_repo = Path(tmpdir) / "repo"
                shutil.copytree(self.repo_path, tmp_repo)

                # Apply mutation
                mutated_path = tmp_repo / target_file.relative_to(self.repo_path)
                mutated_path.write_text(mutated_code)

                # Run test
                try:
                    result = subprocess.run(
                        test_command,
                        shell=True,
                        cwd=str(tmp_repo),
                        capture_output=True,
                        timeout=60
                    )
                except subprocess.TimeoutExpired:
                    continue
                except Exception:
                    continue

                # Only admit task if test FAILS
                if result.returncode != 0:
                    rel_path = target_file.relative_to(self.repo_path)
                    task_id = f"{rel_path.stem}_{entity.name}_{modifier.name}"

                    return Task(
                        id=task_id,
                        description=f"Fix the bug in {rel_path}::{entity.name}: {modifier.explanation}",
                        repo_path=str(self.repo_path),
                        target_file=str(rel_path),
                        test_command=test_command,
                        setup_commands=[],
                        mutation_patch=patch,
                        mutated_code=mutated_code,
                    )

        return None

    def _discover_entities(self, file_path: Path) -> list:
        """
        Discover code entities (functions, classes) in file.

        CRITICAL: Uses adapter-based entity extraction from swesmith.bug_gen.adapters.
        The get_entities_from_file dict maps file extensions to extraction functions.
        Each function populates an entities list in-place.
        """
        from swesmith.bug_gen.adapters import get_entities_from_file

        entities = []
        extract_fn = get_entities_from_file.get(self.file_ext)
        if extract_fn:
            extract_fn(entities, str(file_path), max_entities=-1)
        return entities

    def _find_test_file(self, source_file: Path) -> Path | None:
        """Find corresponding test file - MUST exist."""
        test_name = f"test_{source_file.stem}.py"
        for test_dir in ["tests", "test", "backend/tests"]:
            test_path = self.repo_path / test_dir / test_name
            if test_path.exists():
                return test_path
        return None

    def _build_test_command(self, test_file: Path, entity_name: str) -> str:
        """Build test command targeting specific entity."""
        rel_test = test_file.relative_to(self.repo_path)
        return f"pytest {rel_test} -k {entity_name} -v"

    def _create_patch(self, file_path: Path, original: str, mutated: str) -> str:
        """
        Create unified diff patch.

        CRITICAL: Uses a/ and b/ prefixes for patch -p1 compatibility.
        """
        import difflib
        original_lines = original.splitlines(keepends=True)
        mutated_lines = mutated.splitlines(keepends=True)

        # Use relative path
        rel_path = file_path.relative_to(self.repo_path)

        # CRITICAL: Add a/ and b/ prefixes for -p1 compatibility
        diff = difflib.unified_diff(
            original_lines, mutated_lines,
            fromfile=f"a/{rel_path}",
            tofile=f"b/{rel_path}"
        )
        return ''.join(diff)

    def to_jsonl(self, tasks: list[Task], output_path: Path):
        """Write tasks to JSONL for GEPA."""
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w') as f:
            for task in tasks:
                f.write(json.dumps(task.to_dict()) + '\n')
