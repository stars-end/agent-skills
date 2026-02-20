def compare_semver(a: str, b: str) -> int:
    """Compare semantic versions. Returns -1 if a<b, 0 if a==b, 1 if a>b."""
    def parse(v: str):
        parts = v.split('-', 1)
        release = tuple(int(x) for x in parts[0].split('.'))
        prerelease = parts[1].split('.') if len(parts) > 1 else None
        return release, prerelease

    def cmp_pre(pa, pb):
        if pa is None and pb is None:
            return 0
        if pa is None:
            return 1
        if pb is None:
            return -1
        for i in range(max(len(pa), len(pb))):
            if i >= len(pa):
                return -1
            if i >= len(pb):
                return 1
            xa, xb = pa[i], pb[i]
            an, bn = xa.isdigit(), xb.isdigit()
            if an and bn:
                if (d := int(xa) - int(xb)) != 0:
                    return 1 if d > 0 else -1
            elif an:
                return -1
            elif bn:
                return 1
            elif xa != xb:
                return -1 if xa < xb else 1
        return 0

    ar, ap = parse(a)
    br, bp = parse(b)
    if ar < br:
        return -1
    if ar > br:
        return 1
    return cmp_pre(ap, bp)


import pytest

def test_equal_versions():
    assert compare_semver("1.0.0", "1.0.0") == 0

def test_major_difference():
    assert compare_semver("2.0.0", "1.9.9") == 1
    assert compare_semver("1.0.0", "2.0.0") == -1

def test_minor_difference():
    assert compare_semver("1.2.0", "1.1.9") == 1
    assert compare_semver("1.0.5", "1.1.0") == -1

def test_patch_difference():
    assert compare_semver("1.0.1", "1.0.0") == 1
    assert compare_semver("1.0.0", "1.0.1") == -1

def test_prerelease_lower_than_release():
    assert compare_semver("1.0.0-alpha", "1.0.0") == -1
    assert compare_semver("1.0.0", "1.0.0-beta") == 1

def test_prerelease_lexicographic():
    assert compare_semver("1.0.0-alpha", "1.0.0-beta") == -1
    assert compare_semver("1.0.0-beta", "1.0.0-alpha") == 1
    assert compare_semver("1.0.0-alpha.1", "1.0.0-alpha.2") == -1

def test_numeric_vs_string_prerelease():
    assert compare_semver("1.0.0-1", "1.0.0-alpha") == -1
    assert compare_semver("1.0.0-alpha.1", "1.0.0-alpha.beta") == -1

def test_prerelease_field_count():
    assert compare_semver("1.0.0-alpha", "1.0.0-alpha.1") == -1
    assert compare_semver("1.0.0-alpha.1.beta", "1.0.0-alpha.1") == 1
