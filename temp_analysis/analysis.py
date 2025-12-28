#!/usr/bin/env python3
"""
Change Analysis Module

Provides reusable functions for analyzing git changes, categorizing files,
and determining change significance. Used by /merge, /sync-coordination, /guardrails.
"""

import subprocess
import json
from typing import Dict, List, Tuple
from pathlib import Path


def _default_branch() -> str:
    try:
        # Try remote HEAD
        import subprocess
        result = subprocess.run(
            ['git', 'remote', 'show', 'origin'], capture_output=True, text=True
        )
        for line in result.stdout.splitlines():
            if 'HEAD branch:' in line:
                return line.split(':', 1)[1].strip()
    except Exception:
        pass
    return 'master'


class ChangeAnalyzer:
    """Analyze git changes and categorize by type"""

    # File categorization patterns
    PATTERNS = {
        'schema': ['supabase/migrations/', 'supabase/schemas/'],
        'auth': ['backend/auth/'],
        'api': ['backend/api/', 'backend/services/'],
        'frontend': ['frontend/src/'],
        'config': ['.json', '.toml', '.yaml', '.yml', '.ini'],
        'docs': ['docs/', 'README.md', '*.md'],
        'tests': ['.test.', '.spec.', 'tests/', '__tests__/'],
    }

    def __init__(self, target_branch: str = None):
        self.target_branch = target_branch or _default_branch()

    def analyze_changes(self, committed: bool = False) -> Dict:
        """
        Analyze current changes and categorize them.

        Args:
            committed: If True, analyze committed changes vs target branch
                      If False, analyze uncommitted changes

        Returns:
            Dictionary with categorized changes and statistics
        """
        if committed:
            changed_files = self._get_committed_changes()
            stats = self._get_committed_stats()
        else:
            changed_files = self._get_uncommitted_changes()
            stats = self._get_uncommitted_stats()

        categorized = self._categorize_files(changed_files)
        significance = self._assess_significance(stats, categorized)

        return {
            'files': {
                'all': changed_files,
                'count': len(changed_files),
                'by_category': categorized
            },
            'stats': stats,
            'significance': significance,
            'categories_detected': [k for k, v in categorized.items() if v]
        }

    def _get_uncommitted_changes(self) -> List[str]:
        """Get list of uncommitted changed files"""
        result = subprocess.run(
            ['git', 'diff', '--name-only', 'HEAD'],
            capture_output=True,
            text=True
        )
        return [f for f in result.stdout.strip().split('\n') if f]

    def _get_committed_changes(self) -> List[str]:
        """Get list of files changed vs target branch"""
        result = subprocess.run(
            ['git', 'diff', '--name-only', f'origin/{self.target_branch}...HEAD'],
            capture_output=True,
            text=True
        )
        return [f for f in result.stdout.strip().split('\n') if f]

    def _get_uncommitted_stats(self) -> Dict:
        """Get line change statistics for uncommitted changes"""
        result = subprocess.run(
            ['git', 'diff', '--stat', 'HEAD'],
            capture_output=True,
            text=True
        )
        return self._parse_stat_output(result.stdout)

    def _get_committed_stats(self) -> Dict:
        """Get line change statistics for committed changes"""
        result = subprocess.run(
            ['git', 'diff', '--stat', f'origin/{self.target_branch}...HEAD'],
            capture_output=True,
            text=True
        )
        return self._parse_stat_output(result.stdout)

    def _parse_stat_output(self, output: str) -> Dict:
        """Parse git diff --stat output"""
        # Last line has summary: "3 files changed, 45 insertions(+), 12 deletions(-)"
        lines = output.strip().split('\n')
        if not lines:
            return {'insertions': 0, 'deletions': 0, 'net': 0}

        summary = lines[-1]

        insertions = 0
        deletions = 0

        if 'insertion' in summary:
            parts = summary.split('insertion')
            num_str = parts[0].strip().split()[-1]
            insertions = int(num_str)

        if 'deletion' in summary:
            parts = summary.split('deletion')
            num_str = parts[0].strip().split()[-1]
            deletions = int(num_str)

        return {
            'insertions': insertions,
            'deletions': deletions,
            'net': insertions + deletions
        }

    def _categorize_files(self, files: List[str]) -> Dict[str, List[str]]:
        """Categorize files by type"""
        categorized = {cat: [] for cat in self.PATTERNS.keys()}

        for file in files:
            for category, patterns in self.PATTERNS.items():
                if self._matches_patterns(file, patterns):
                    categorized[category].append(file)
                    break  # File belongs to first matching category

        return categorized

    def _matches_patterns(self, file: str, patterns: List[str]) -> bool:
        """Check if file matches any pattern"""
        for pattern in patterns:
            if pattern.startswith('.'):
                # Extension pattern
                if file.endswith(pattern):
                    return True
            elif '*' in pattern:
                # Glob pattern (simple check)
                if pattern.replace('*', '') in file:
                    return True
            else:
                # Path prefix pattern
                if pattern in file:
                    return True
        return False

    def _assess_significance(self, stats: Dict, categorized: Dict) -> str:
        """Assess overall significance of changes"""
        net_lines = stats['net']

        # High significance indicators
        if categorized['schema'] or categorized['auth']:
            return 'HIGH'
        if net_lines > 500:
            return 'HIGH'

        # Medium significance indicators
        if categorized['api'] or categorized['config']:
            return 'MEDIUM'
        if net_lines > 100:
            return 'MEDIUM'

        # Low significance
        return 'LOW'


def analyze_current_changes(target_branch: str = 'agent-coordination',
                            committed: bool = False) -> Dict:
    """
    Convenience function to analyze changes.

    Usage:
        from lib.analysis import analyze_current_changes
        result = analyze_current_changes()
        print(result['significance'])  # HIGH, MEDIUM, or LOW
    """
    analyzer = ChangeAnalyzer(target_branch)
    return analyzer.analyze_changes(committed)


def format_analysis_output(analysis: Dict) -> str:
    """Format analysis results for display"""
    output = []
    output.append("📊 Change Analysis\n")
    output.append(f"Files changed: {analysis['files']['count']}")
    output.append(f"Lines changed: {analysis['stats']['insertions']}+ {analysis['stats']['deletions']}-")
    output.append(f"\nCategories detected:")

    for category in analysis['categories_detected']:
        files = analysis['files']['by_category'][category]
        output.append(f"├─ {category.capitalize()}: ✅ ({len(files)} files)")

    output.append(f"\n📈 Significance: {analysis['significance']}")

    return '\n'.join(output)


if __name__ == '__main__':
    # CLI usage
    import sys

    committed = '--committed' in sys.argv
    target = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('--') else 'agent-coordination'

    analysis = analyze_current_changes(target, committed)

    if '--json' in sys.argv:
        print(json.dumps(analysis, indent=2))
    else:
        print(format_analysis_output(analysis))
