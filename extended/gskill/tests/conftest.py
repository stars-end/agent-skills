"""Pytest configuration for gskill tests."""

import sys
from pathlib import Path

# Add repo root to path for imports
repo_root = Path(__file__).parent.parent.parent.parent
if str(repo_root) not in sys.path:
    sys.path.insert(0, str(repo_root))
