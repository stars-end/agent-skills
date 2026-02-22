"""
prime-radiant-ai Repository Adapter.

Configures task generation for prime-radiant-ai specific patterns.
"""

from dataclasses import dataclass
from pathlib import Path
import fnmatch


@dataclass
class RepoAdapter:
    """Configuration for task generation on a specific repo."""

    name: str
    repo_path: Path
    language: str
    target_patterns: list[str]
    test_patterns: list[str]
    exclude_patterns: list[str]
    test_command_template: str
    test_dirs: list[str] | None = None
    test_mapping: dict[str, str] | None = None  # source_file -> test_file

    def matches_exclude(self, file_path: Path, repo_root: Path) -> bool:
        """Check if file matches any exclude pattern using glob matching."""
        rel_path = str(file_path.relative_to(repo_root))
        for pattern in self.exclude_patterns:
            if fnmatch.fnmatch(rel_path, pattern):
                return True
            if fnmatch.fnmatch(file_path.name, pattern):
                return True
        return False


PRIME_RADIANT_ADAPTER = RepoAdapter(
    name="prime-radiant-ai",
    repo_path=Path("~/prime-radiant-ai").expanduser(),
    language="python",
    target_patterns=[
        "backend/services/*.py",
        "backend/api/v2/*.py",
        "backend/db/*.py",
    ],
    test_patterns=[
        "tests/test_*.py",
        "backend/tests/test_*.py",
    ],
    # GLOB patterns - these actually match paths
    exclude_patterns=[
        "*/migrations/*",  # Matches backend/migrations/versions/xxx.py
        "*/fixtures/*",  # Matches tests/fixtures/xxx.py
        "*/debug_*.py",  # Matches any debug_ prefixed file
        "*/apply_migration*.py",  # Matches migration scripts
        "*/create_*.py",  # Matches setup scripts
    ],
    test_command_template="pytest {test_file} -v",
    # Test directories to search
    test_dirs=["tests", "backend/tests"],
    # Explicit test mappings for non-standard naming
    # Format: "backend/services/foo_service.py" -> "backend/tests/test_foo.py"
    test_mapping={
        # Add mappings here if needed, e.g.:
        # "backend/services/health_service.py": "backend/tests/test_health.py",
    },
)


def get_prime_radiant_tasks(max_tasks: int = 100) -> list[dict]:
    """Generate tasks for prime-radiant-ai."""
    from extended.gskill.lib.task_generator import TaskGenerator

    gen = TaskGenerator(
        repo_path=PRIME_RADIANT_ADAPTER.repo_path,
        language=PRIME_RADIANT_ADAPTER.language,
        test_dirs=PRIME_RADIANT_ADAPTER.test_dirs,
        test_mapping=PRIME_RADIANT_ADAPTER.test_mapping,
    )

    gen.set_target_patterns(PRIME_RADIANT_ADAPTER.target_patterns)
    gen.set_exclude_patterns(PRIME_RADIANT_ADAPTER.exclude_patterns)

    return [t.to_dict() for t in gen.generate_tasks(max_tasks=max_tasks)]
