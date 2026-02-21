"""End-to-end tests (slow, skip in CI)."""
import pytest


@pytest.mark.slow
def test_full_pipeline_on_simple_repo():
    """E2E test on a minimal repo. Skip in CI."""
    # This test is slow and requires:
    # - SWE-smith installed
    # - GEPA installed
    # - opencode available
    # - A repo with tests
    #
    # Run manually with: pytest -m slow extended/gskill/tests/test_e2e.py
    pytest.skip("E2E test requires full environment setup")
