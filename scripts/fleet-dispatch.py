#!/usr/bin/env python
"""
fleet-dispatch.py — thin CLI wrapper around lib.fleet.FleetDispatcher

Purpose
-------
Provides a stable executable interface for Slack/Clawdbot + humans to:
- dispatch Beads-linked work to OpenCode/Jules backends
- check status / wait
- finalize PR (deterministic via OpenCode /shell)

This avoids embedding large python one-liners in prompts.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


AGENT_SKILLS_ROOT = Path(__file__).resolve().parents[1]


def _load_prompt(args: argparse.Namespace) -> str:
    if getattr(args, "prompt", None):
        return args.prompt
    prompt_file = getattr(args, "prompt_file", None)
    if prompt_file:
        if prompt_file == "-":
            return sys.stdin.read()
        return Path(prompt_file).read_text()
    raise SystemExit("missing prompt: use --prompt or --prompt-file")


def _dispatcher():
    # Ensure `import lib.fleet` works when invoked from any CWD.
    sys.path.insert(0, str(AGENT_SKILLS_ROOT))
    from lib.fleet import FleetDispatcher  # type: ignore

    return FleetDispatcher()


def _print(obj: object, as_json: bool) -> None:
    if as_json:
        print(json.dumps(obj, indent=2, sort_keys=True))
    else:
        print(obj)


def cmd_dispatch(args: argparse.Namespace) -> int:
    dispatcher = _dispatcher()
    prompt = _load_prompt(args)

    mode = args.mode
    finalize = args.finalize_pr or args.smoke_pr
    if args.smoke_pr:
        mode = "smoke"

    result = dispatcher.dispatch(
        beads_id=args.beads,
        prompt=prompt,
        repo=args.repo,
        mode=mode,
        preferred_backend=args.backend,
        system_prompt=args.system_prompt,
        slack_message_ts=args.slack_message_ts,
        slack_thread_ts=args.slack_thread_ts,
    )

    payload: dict[str, object] = {
        "success": result.success,
        "beads_id": args.beads,
        "repo": args.repo,
        "mode": mode,
        "session_id": result.session_id,
        "backend_name": result.backend_name,
        "backend_type": result.backend_type,
        "vm_url": result.vm_url,
        "worktree_path": result.worktree_path,
        "was_duplicate": result.was_duplicate,
        "error": result.error,
        "failure_code": result.failure_code,
    }

    if result.success and finalize:
        pr_url = dispatcher.finalize_pr(
            session_id=result.session_id,
            beads_id=args.beads,
            smoke_mode=(mode == "smoke"),
        )
        payload["finalize_pr"] = {"attempted": True, "pr_url": pr_url}
        if not pr_url:
            payload["finalize_pr"]["status"] = dispatcher.get_status(result.session_id)

    _print(payload, args.json)
    return 0 if result.success else 2


def cmd_status(args: argparse.Namespace) -> int:
    dispatcher = _dispatcher()
    status = dispatcher.get_status(args.session)
    _print(status, args.json)
    return 0


def cmd_wait(args: argparse.Namespace) -> int:
    dispatcher = _dispatcher()
    status = dispatcher.wait_for_completion(
        session_id=args.session,
        poll_interval_sec=args.poll_interval,
        max_polls=args.max_polls,
    )
    _print(status, args.json)
    return 0


def cmd_finalize_pr(args: argparse.Namespace) -> int:
    dispatcher = _dispatcher()
    pr_url = dispatcher.finalize_pr(
        session_id=args.session,
        beads_id=args.beads,
        smoke_mode=args.smoke,
    )
    payload = {"session_id": args.session, "beads_id": args.beads, "pr_url": pr_url}
    if not pr_url:
        payload["status"] = dispatcher.get_status(args.session)
    _print(payload, args.json)
    return 0 if pr_url else 2


def cmd_abort(args: argparse.Namespace) -> int:
    dispatcher = _dispatcher()
    record = dispatcher.state_store.find_by_session_id(args.session)
    if not record:
        _print({"success": False, "error": "Session not found in fleet-state.json"}, args.json)
        return 2
    backend = dispatcher.get_backend(record.backend_name)
    if not backend:
        _print({"success": False, "error": f"Backend not found: {record.backend_name}"}, args.json)
        return 2
    ok = backend.abort_session(args.session)
    _print({"success": bool(ok), "session_id": args.session, "backend": record.backend_name}, args.json)
    return 0 if ok else 2


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="fleet-dispatch", description="FleetDispatcher CLI wrapper")
    p.add_argument("--json", action="store_true", help="Emit JSON")
    sub = p.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("dispatch", help="Dispatch a task (returns immediately)")
    d.add_argument("--beads", required=True, help="Beads id (bd-xxx)")
    d.add_argument("--repo", required=True, help="Repo name (e.g. prime-radiant-ai)")
    d.add_argument("--mode", default="real", choices=["real", "smoke"], help="Dispatch mode")
    d.add_argument("--backend", default=None, help="Preferred backend name (e.g. epyc6, macmini, jules-cloud)")
    d.add_argument("--prompt", default=None, help="Prompt text")
    d.add_argument("--prompt-file", default=None, help="Prompt file path or '-' for stdin")
    d.add_argument("--system-prompt", default=None, help="Optional system context")
    d.add_argument("--finalize-pr", action="store_true", help="Attempt PR finalization after dispatch")
    d.add_argument("--smoke-pr", action="store_true", help="Shortcut: mode=smoke + finalize PR (push --no-verify)")
    d.add_argument("--slack-message-ts", default=None, help="Slack message ts (for edits)")
    d.add_argument("--slack-thread-ts", default=None, help="Slack thread ts")
    d.set_defaults(func=cmd_dispatch)

    s = sub.add_parser("status", help="Get current status for a session")
    s.add_argument("--session", required=True, help="OpenCode/Jules session id")
    s.set_defaults(func=cmd_status)

    w = sub.add_parser("wait", help="Poll until completion")
    w.add_argument("--session", required=True, help="OpenCode/Jules session id")
    w.add_argument("--poll-interval", type=int, default=60, help="Poll interval seconds")
    w.add_argument("--max-polls", type=int, default=30, help="Max poll iterations")
    w.set_defaults(func=cmd_wait)

    f = sub.add_parser("finalize-pr", help="Finalize PR for an OpenCode session")
    f.add_argument("--session", required=True, help="OpenCode session id")
    f.add_argument("--beads", required=True, help="Beads id (bd-xxx)")
    f.add_argument("--smoke", action="store_true", help="Smoke mode (push --no-verify + allow-empty commit)")
    f.set_defaults(func=cmd_finalize_pr)

    a = sub.add_parser("abort", help="Abort a running session (best-effort)")
    a.add_argument("--session", required=True, help="Session id")
    a.set_defaults(func=cmd_abort)

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
