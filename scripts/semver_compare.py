"""
Semantic version comparison following semver.org precedence rules.
Returns: -1 if a < b, 0 if a == b, 1 if a > b
"""
import re
from typing import Tuple, List, Union

# Semver regex from semver.org
SEMVER_PATTERN = re.compile(
    r'^(?P<major>0|[1-9]\d*)'
    r'(?:\.(?P<minor>0|[1-9]\d*))?'
    r'(?:\.(?P<patch>0|[1-9]\d*))?'
    r'(?:-(?P<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)'
    r'(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?'
    r'(?:\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'
)


def parse_version(version: str) -> Tuple[int, int, int, List[Union[int, str]]]:
    """
    Parse a semver string into comparable components.
    Returns (major, minor, patch, prerelease_parts).
    Build metadata is ignored for precedence.
    """
    if not version or not isinstance(version, str):
        raise ValueError(f"Invalid version string: {version!r}")

    match = SEMVER_PATTERN.match(version.strip())
    if not match:
        raise ValueError(f"Invalid semver format: {version!r}")

    major = int(match.group('major'))
    minor = int(match.group('minor') or 0)
    patch = int(match.group('patch') or 0)

    # Parse prerelease into comparable parts
    prerelease_str = match.group('prerelease')
    prerelease_parts: List[Union[int, str]] = []

    if prerelease_str:
        for part in prerelease_str.split('.'):
            # Numeric identifiers must not include leading zeros
            if part.isdigit():
                prerelease_parts.append(int(part))
            else:
                prerelease_parts.append(part)

    return (major, minor, patch, prerelease_parts)


def compare_prerelease(a_parts: List[Union[int, str]],
                       b_parts: List[Union[int, str]]) -> int:
    """
    Compare prerelease identifiers.
    - Empty prerelease (release version) has higher precedence than any prerelease
    - Numeric identifiers compared as integers
    - Alphanumeric identifiers compared lexically (ASCII sort)
    - Numeric < Alphanumeric
    - Longer prerelease has higher precedence if all preceding parts equal
    """
    # Empty prerelease (release) > any prerelease
    if not a_parts and not b_parts:
        return 0
    if not a_parts and b_parts:
        return 1  # a is release, b is prerelease
    if a_parts and not b_parts:
        return -1  # a is prerelease, b is release

    # Compare part by part
    for a_part, b_part in zip(a_parts, b_parts):
        # Both numeric
        if isinstance(a_part, int) and isinstance(b_part, int):
            if a_part < b_part:
                return -1
            if a_part > b_part:
                return 1
        # Both strings
        elif isinstance(a_part, str) and isinstance(b_part, str):
            if a_part < b_part:
                return -1
            if a_part > b_part:
                return 1
        # Numeric < string (per semver spec)
        elif isinstance(a_part, int) and isinstance(b_part, str):
            return -1
        else:  # a is str, b is int
            return 1

    # All compared parts equal; longer prerelease has higher precedence
    if len(a_parts) < len(b_parts):
        return -1
    if len(a_parts) > len(b_parts):
        return 1
    return 0


def compare_semver(a: str, b: str) -> int:
    """
    Compare two semantic version strings.

    Args:
        a: First version string (e.g., "1.2.3" or "1.0.0-alpha.1")
        b: Second version string

    Returns:
        -1 if a < b
         0 if a == b
         1 if a > b

    Raises:
        ValueError: If either version string is invalid

    Edge cases handled:
        - Missing minor/patch (defaults to 0)
        - Prerelease versions (alpha < beta < rc < release)
        - Build metadata (ignored for comparison)
        - Leading zeros in numeric identifiers (rejected per semver)
        - Mixed numeric/alphanumeric prerelease parts
    """
    a_major, a_minor, a_patch, a_pre = parse_version(a)
    b_major, b_minor, b_patch, b_pre = parse_version(b)

    # Compare major.minor.patch
    if a_major != b_major:
        return -1 if a_major < b_major else 1
    if a_minor != b_minor:
        return -1 if a_minor < b_minor else 1
    if a_patch != b_patch:
        return -1 if a_patch < b_patch else 1

    # Compare prerelease
    return compare_prerelease(a_pre, b_pre)


# ============================================================================
# Pytest-style tests
# ============================================================================

import pytest


class TestSemverComparison:
    """Test suite for compare_semver function."""

    def test_basic_versions(self):
        """Test basic version comparison."""
        assert compare_semver("1.0.0", "2.0.0") == -1
        assert compare_semver("2.0.0", "1.0.0") == 1
        assert compare_semver("1.0.0", "1.0.0") == 0

    def test_minor_and_patch_levels(self):
        """Test comparison at minor and patch levels."""
        assert compare_semver("1.2.0", "1.3.0") == -1
        assert compare_semver("1.2.9", "1.2.10") == -1
        assert compare_semver("2.1.0", "2.0.9") == 1
        assert compare_semver("1.0.1", "1.0.1") == 0

    def test_partial_versions_default_to_zero(self):
        """Test that missing minor/patch default to 0."""
        assert compare_semver("1", "1.0.0") == 0
        assert compare_semver("1.2", "1.2.0") == 0
        assert compare_semver("2", "1.9.9") == 1

    def test_prerelease_vs_release(self):
        """Test that prerelease has lower precedence than release."""
        assert compare_semver("1.0.0-alpha", "1.0.0") == -1
        assert compare_semver("1.0.0", "1.0.0-beta") == 1
        assert compare_semver("1.0.0-rc.1", "1.0.0") == -1

    def test_prerelease_alphanumeric_comparison(self):
        """Test alphanumeric prerelease identifiers."""
        assert compare_semver("1.0.0-alpha", "1.0.0-beta") == -1
        assert compare_semver("1.0.0-beta", "1.0.0-alpha") == 1
        assert compare_semver("1.0.0-rc.1", "1.0.0-rc.2") == -1
        assert compare_semver("1.0.0-alpha.1", "1.0.0-alpha.2") == -1

    def test_numeric_vs_alphanumeric_prerelease(self):
        """Test that numeric identifiers have lower precedence than alphanumeric."""
        assert compare_semver("1.0.0-1", "1.0.0-alpha") == -1
        assert compare_semver("1.0.0-alpha", "1.0.0-1") == 1
        assert compare_semver("1.0.0-1.beta", "1.0.0-1.alpha") == 1

    def test_prerelease_different_lengths(self):
        """Test prerelease identifiers with different lengths."""
        assert compare_semver("1.0.0-alpha", "1.0.0-alpha.1") == -1
        assert compare_semver("1.0.0-alpha.1", "1.0.0-alpha.1.1") == -1
        assert compare_semver("1.0.0-alpha.beta", "1.0.0-alpha.beta.1") == -1

    def test_build_metadata_ignored(self):
        """Test that build metadata is ignored for precedence."""
        assert compare_semver("1.0.0+build123", "1.0.0") == 0
        assert compare_semver("1.0.0", "1.0.0+build456") == 0
        assert compare_semver("1.0.0-alpha+build", "1.0.0-alpha") == 0
        assert compare_semver("1.0.0+abc", "1.0.0+xyz") == 0


class TestSemverEdgeCases:
    """Test edge cases and error handling."""

    def test_invalid_version_raises(self):
        """Test that invalid versions raise ValueError."""
        with pytest.raises(ValueError):
            compare_semver("", "1.0.0")

        with pytest.raises(ValueError):
            compare_semver("1.0.0", "")

        with pytest.raises(ValueError):
            compare_semver("not.a.version", "1.0.0")

    def test_leading_zeros_rejected(self):
        """Test that leading zeros in numeric identifiers are rejected."""
        with pytest.raises(ValueError):
            compare_semver("01.0.0", "1.0.0")

        with pytest.raises(ValueError):
            compare_semver("1.01.0", "1.0.0")

    def test_whitespace_handling(self):
        """Test that leading/trailing whitespace is handled."""
        assert compare_semver(" 1.0.0 ", "1.0.0") == 0
        assert compare_semver("\t1.0.0\n", "1.0.0") == 0

    def test_version_with_v_prefix_rejected(self):
        """Test that 'v' prefix is not part of semver spec."""
        with pytest.raises(ValueError):
            compare_semver("v1.0.0", "1.0.0")


if __name__ == "__main__":
    # Run tests with pytest
    pytest.main([__file__, "-v"])
