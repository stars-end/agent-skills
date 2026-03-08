#!/usr/bin/env python3
"""
Tests for dx-loop baton semantics
"""

import sys
from pathlib import Path

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "scripts" / "lib"))

from dx_loop.baton import BatonPhase, BatonManager, ReviewVerdict


def test_baton_lifecycle():
    """Test baton implement/review lifecycle"""
    manager = BatonManager(max_attempts=3, max_revisions=3)
    
    # Start implement
    state = manager.start_implement("bd-test")
    assert state.phase == BatonPhase.IMPLEMENT
    assert state.attempt == 1
    
    # Complete implement with PR artifacts
    state = manager.complete_implement(
        "bd-test",
        pr_url="https://github.com/example/test/pull/1",
        pr_head_sha="abc123def456789012345678901234567890abcd",
    )
    assert state.phase == BatonPhase.REVIEW
    assert state.pr_url is not None
    assert state.pr_head_sha is not None
    
    # Complete review with APPROVED
    state = manager.complete_review(
        "bd-test",
        ReviewVerdict.APPROVED,
        pr_url="https://github.com/example/test/pull/1",
        pr_head_sha="abc123def456789012345678901234567890abcd",
    )
    assert state.phase == BatonPhase.COMPLETE
    assert state.verdict == ReviewVerdict.APPROVED
    
    print("✓ Baton lifecycle works")


def test_baton_revision_required():
    """Test revision required cycle"""
    manager = BatonManager(max_attempts=3, max_revisions=2)
    
    manager.start_implement("bd-test2")
    manager.complete_implement(
        "bd-test2",
        pr_url="https://github.com/example/test/pull/2",
        pr_head_sha="abc123def456789012345678901234567890abcd",
    )
    
    # First revision
    state = manager.complete_review("bd-test2", ReviewVerdict.REVISION_REQUIRED)
    assert state.phase == BatonPhase.IMPLEMENT
    assert state.revision_count == 1
    
    # Second revision
    manager.complete_implement("bd-test2")
    state = manager.complete_review("bd-test2", ReviewVerdict.REVISION_REQUIRED)
    assert state.phase == BatonPhase.FAILED
    assert state.revision_count == 2
    
    print("✓ Revision required cycle works")


def test_missing_pr_artifacts():
    """Test that missing PR artifacts blocks completion"""
    manager = BatonManager()
    
    manager.start_implement("bd-test3")
    manager.complete_implement("bd-test3")  # No PR artifacts
    
    state = manager.complete_review("bd-test3", ReviewVerdict.APPROVED)
    assert state.phase == BatonPhase.FAILED
    assert state.metadata.get("failure_reason") == "missing_pr_artifacts"
    
    print("✓ Missing PR artifacts blocks completion")


if __name__ == "__main__":
    test_baton_lifecycle()
    test_baton_revision_required()
    test_missing_pr_artifacts()
    print("\nAll baton tests passed!")
