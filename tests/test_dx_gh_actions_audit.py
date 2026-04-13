"""Tests for cross-repo GitHub Actions failure collector/classifier."""

from __future__ import annotations

import sys
from pathlib import Path


LIB_DIR = Path(__file__).resolve().parent.parent / "scripts" / "lib"
if str(LIB_DIR) not in sys.path:
    sys.path.insert(0, str(LIB_DIR))

from github_actions_audit import build_report  # noqa: E402


def _result_ok(data):
    return {"ok": True, "data": data}


def _result_err(code: str, message: str, stderr: str = ""):
    return {"ok": False, "error_code": code, "message": message, "stderr": stderr}


def _relevance_calls(args, repo: str, default_branch: str = "master", open_prs=None):
    if open_prs is None:
        open_prs = []
    if args[:3] == ["repo", "view", repo]:
        return _result_ok({"defaultBranchRef": {"name": default_branch}})
    if args[:4] == ["pr", "list", "--repo", repo]:
        return _result_ok(open_prs)
    return None


def test_group_becomes_stale_when_newer_success_exists():
    repo = "stars-end/llm-common"

    def fake_json(args):
        relevance = _relevance_calls(args, repo)
        if relevance is not None:
            return relevance
        if args[:4] == ["run", "list", "--repo", repo] and "--status" in args:
            return _result_ok(
                [
                    {
                        "databaseId": 1001,
                        "workflowName": "CI",
                        "headBranch": "master",
                        "headSha": "abc1234",
                        "createdAt": "2026-04-10T00:00:00Z",
                        "displayTitle": "fix lint",
                        "event": "push",
                        "conclusion": "failure",
                    }
                ]
            )
        if args[:4] == ["run", "list", "--repo", repo] and "--status" not in args:
            return _result_ok(
                [
                    {
                        "databaseId": 1002,
                        "workflowName": "CI",
                        "headBranch": "master",
                        "headSha": "def5678",
                        "createdAt": "2026-04-11T00:00:00Z",
                        "conclusion": "success",
                        "status": "completed",
                        "event": "push",
                    }
                ]
            )
        if args[:3] == ["run", "view", "1001"]:
            return _result_ok({"jobs": [{"name": "lint", "conclusion": "failure"}]})
        raise AssertionError(f"unexpected args: {args}")

    def fake_text(args):
        if args[:3] == ["run", "view", "1001"]:
            return _result_ok("ERROR: lint failed")
        raise AssertionError(f"unexpected args: {args}")

    report = build_report(
        repos=[repo],
        failed_run_limit=30,
        recent_run_limit=50,
        gh_json_runner=fake_json,
        gh_text_runner=fake_text,
    )

    assert report["summary"]["active_groups"] == 0
    assert report["summary"]["stale_groups"] == 1
    group = report["stale_groups"][0]
    assert group["classification"]["status"] == "stale"
    assert group["classification"]["reason"] == "newer_success_run"
    assert group["latest_failure"]["run_url"] == f"https://github.com/{repo}/actions/runs/1001"


def test_group_remains_active_without_newer_success():
    repo = "stars-end/prime-radiant-ai"

    def fake_json(args):
        relevance = _relevance_calls(args, repo)
        if relevance is not None:
            return relevance
        if args[:4] == ["run", "list", "--repo", repo] and "--status" in args:
            return _result_ok(
                [
                    {
                        "databaseId": 2001,
                        "workflowName": "Dependency & Security Audit",
                        "headBranch": "master",
                        "headSha": "aaa1111",
                        "createdAt": "2026-04-12T00:00:00Z",
                        "displayTitle": "deps",
                        "event": "push",
                        "conclusion": "failure",
                    }
                ]
            )
        if args[:4] == ["run", "list", "--repo", repo] and "--status" not in args:
            return _result_ok(
                [
                    {
                        "databaseId": 2001,
                        "workflowName": "Dependency & Security Audit",
                        "headBranch": "master",
                        "headSha": "aaa1111",
                        "createdAt": "2026-04-12T00:00:00Z",
                        "conclusion": "failure",
                        "status": "completed",
                        "event": "push",
                    }
                ]
            )
        if args[:3] == ["run", "view", "2001"]:
            return _result_ok({"jobs": [{"name": "security", "conclusion": "failure"}]})
        raise AssertionError(f"unexpected args: {args}")

    def fake_text(args):
        if args[:3] == ["run", "view", "2001"]:
            return _result_ok("pnpm audit: Critical severity vulnerability found")
        raise AssertionError(f"unexpected args: {args}")

    report = build_report(
        repos=[repo],
        failed_run_limit=30,
        recent_run_limit=50,
        gh_json_runner=fake_json,
        gh_text_runner=fake_text,
    )

    assert report["summary"]["active_groups"] == 1
    assert report["summary"]["stale_groups"] == 0
    group = report["active_groups"][0]
    assert group["classification"]["status"] == "active"
    assert group["job"] == "security"
    assert "vulnerability" in group["signature"].lower()


def test_repo_auth_failure_is_reported_explicitly():
    repo = "stars-end/affordabot"

    def fake_json(_args):
        return _result_err("gh_command_failed", "gh command failed", "HTTP 403: resource not accessible")

    report = build_report(
        repos=[repo],
        failed_run_limit=30,
        recent_run_limit=50,
        gh_json_runner=fake_json,
        gh_text_runner=lambda _args: _result_ok(""),
    )

    assert report["summary"]["repos_error"] == 1
    assert report["repos"][0]["status"] == "error"
    assert report["repo_errors"][0]["repo"] == repo
    assert report["repo_errors"][0]["stage"] == "run_list_failures"


def test_signature_normalization_groups_similar_failures():
    repo = "stars-end/agent-skills"

    def fake_json(args):
        relevance = _relevance_calls(args, repo)
        if relevance is not None:
            return relevance
        if args[:4] == ["run", "list", "--repo", repo] and "--status" in args:
            return _result_ok(
                [
                    {
                        "databaseId": 3001,
                        "workflowName": "CI",
                        "headBranch": "master",
                        "headSha": "111aaaa",
                        "createdAt": "2026-04-10T00:00:00Z",
                        "displayTitle": "run1",
                        "event": "push",
                        "conclusion": "failure",
                    },
                    {
                        "databaseId": 3002,
                        "workflowName": "CI",
                        "headBranch": "master",
                        "headSha": "222bbbb",
                        "createdAt": "2026-04-11T00:00:00Z",
                        "displayTitle": "run2",
                        "event": "push",
                        "conclusion": "failure",
                    },
                ]
            )
        if args[:4] == ["run", "list", "--repo", repo] and "--status" not in args:
            return _result_ok([])
        if args[:3] == ["run", "view", "3001"]:
            return _result_ok({"jobs": [{"name": "tests", "conclusion": "failure"}]})
        if args[:3] == ["run", "view", "3002"]:
            return _result_ok({"jobs": [{"name": "tests", "conclusion": "failure"}]})
        raise AssertionError(f"unexpected args: {args}")

    def fake_text(args):
        if args[:3] == ["run", "view", "3001"]:
            return _result_ok("Error: timeout after 1234ms")
        if args[:3] == ["run", "view", "3002"]:
            return _result_ok("Error: timeout after 9876ms")
        raise AssertionError(f"unexpected args: {args}")

    report = build_report(
        repos=[repo],
        failed_run_limit=30,
        recent_run_limit=50,
        gh_json_runner=fake_json,
        gh_text_runner=fake_text,
    )

    assert report["summary"]["total_groups"] == 1
    assert report["groups"][0]["occurrences"] == 2


def test_closed_branch_group_is_not_active():
    repo = "stars-end/agent-skills"

    def fake_json(args):
        relevance = _relevance_calls(args, repo, default_branch="master", open_prs=[])
        if relevance is not None:
            return relevance
        if args[:4] == ["run", "list", "--repo", repo] and "--status" in args:
            return _result_ok(
                [
                    {
                        "databaseId": 4001,
                        "workflowName": "CI",
                        "headBranch": "feature/closed-pr",
                        "headSha": "abcd1111",
                        "createdAt": "2026-04-12T10:00:00Z",
                        "displayTitle": "closed pr",
                        "event": "pull_request",
                        "conclusion": "failure",
                    }
                ]
            )
        if args[:4] == ["run", "list", "--repo", repo] and "--status" not in args:
            return _result_ok(
                [
                    {
                        "databaseId": 4001,
                        "workflowName": "CI",
                        "headBranch": "feature/closed-pr",
                        "headSha": "abcd1111",
                        "createdAt": "2026-04-12T10:00:00Z",
                        "conclusion": "failure",
                        "status": "completed",
                        "event": "pull_request",
                    }
                ]
            )
        if args[:3] == ["run", "view", "4001"]:
            return _result_ok({"jobs": [{"name": "tests", "conclusion": "failure"}]})
        raise AssertionError(f"unexpected args: {args}")

    def fake_text(args):
        if args[:3] == ["run", "view", "4001"]:
            return _result_ok("Error: failed tests")
        raise AssertionError(f"unexpected args: {args}")

    report = build_report(
        repos=[repo],
        failed_run_limit=30,
        recent_run_limit=50,
        gh_json_runner=fake_json,
        gh_text_runner=fake_text,
    )

    assert report["summary"]["active_groups"] == 0
    assert report["summary"]["stale_groups"] == 1
    assert report["groups"][0]["classification"]["reason"] == "irrelevant_closed_or_non_default_branch"


def test_open_pr_branch_group_remains_active():
    repo = "stars-end/agent-skills"

    def fake_json(args):
        relevance = _relevance_calls(
            args,
            repo,
            default_branch="master",
            open_prs=[{"headRefName": "feature/open-pr", "headRefOid": "aaaa2222"}],
        )
        if relevance is not None:
            return relevance
        if args[:4] == ["run", "list", "--repo", repo] and "--status" in args:
            return _result_ok(
                [
                    {
                        "databaseId": 5001,
                        "workflowName": "CI",
                        "headBranch": "feature/open-pr",
                        "headSha": "aaaa2222",
                        "createdAt": "2026-04-12T12:00:00Z",
                        "displayTitle": "open pr",
                        "event": "pull_request",
                        "conclusion": "failure",
                    }
                ]
            )
        if args[:4] == ["run", "list", "--repo", repo] and "--status" not in args:
            return _result_ok(
                [
                    {
                        "databaseId": 5001,
                        "workflowName": "CI",
                        "headBranch": "feature/open-pr",
                        "headSha": "aaaa2222",
                        "createdAt": "2026-04-12T12:00:00Z",
                        "conclusion": "failure",
                        "status": "completed",
                        "event": "pull_request",
                    }
                ]
            )
        if args[:3] == ["run", "view", "5001"]:
            return _result_ok({"jobs": [{"name": "tests", "conclusion": "failure"}]})
        raise AssertionError(f"unexpected args: {args}")

    def fake_text(args):
        if args[:3] == ["run", "view", "5001"]:
            return _result_ok("Error: failed tests")
        raise AssertionError(f"unexpected args: {args}")

    report = build_report(
        repos=[repo],
        failed_run_limit=30,
        recent_run_limit=50,
        gh_json_runner=fake_json,
        gh_text_runner=fake_text,
    )

    assert report["summary"]["active_groups"] == 1
    assert report["groups"][0]["classification"]["status"] == "active"
