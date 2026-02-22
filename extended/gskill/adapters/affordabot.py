"""
affordabot Repository Adapter.

Configures task generation for affordabot specific patterns.
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

    def matches_exclude(self, file_path: Path, repo_root: Path) -> bool:
        """Check if file matches any exclude pattern using glob matching."""
        rel_path = str(file_path.relative_to(repo_root))
        for pattern in self.exclude_patterns:
            if fnmatch.fnmatch(rel_path, pattern):
                return True
            if fnmatch.fnmatch(file_path.name, pattern):
                return True
        return False


AFFORDABOT_ADAPTER = RepoAdapter(
    name="affordabot",
    repo_path=Path("~/affordabot").expanduser(),
    language="python",

    target_patterns=[
        "backend/services/scraper/*.py",
        "backend/services/extractors/*.py",
        "backend/services/ingestion_service.py",
        "backend/services/search_pipeline_service.py",
        "backend/services/source_service.py",
    ],

    test_patterns=[
        "tests/test_*.py",
        "backend/tests/test_*.py",
    ],

    # GLOB patterns - these actually match paths
    exclude_patterns=[
        "*/verification/*",          # Matches any verification dir
        "*/legacy/*",                # Matches any legacy dir
        "scripts/verification/*",    # Specific verification scripts
        "*/probe_*.py",              # Matches probe scripts
    ],

    test_command_template="pytest {test_file} -v",
)


def get_affordabot_tasks(max_tasks: int = 100) -> list[dict]:
    """Generate tasks for affordabot."""
    from extended.gskill.lib.task_generator import TaskGenerator

    gen = TaskGenerator(
        repo_path=AFFORDABOT_ADAPTER.repo_path,
        language=AFFORDABOT_ADAPTER.language,
    )

    gen.set_target_patterns(AFFORDABOT_ADAPTER.target_patterns)
    gen.set_exclude_patterns(AFFORDABOT_ADAPTER.exclude_patterns)

    return list(gen.generate_tasks(max_tasks=max_tasks))
