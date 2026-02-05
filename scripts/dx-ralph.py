#!/usr/bin/env python3
"""
dx-ralph - Manual OpenCode Ralph Orchestrator (Epic-level, strict context reset)

Implements Beads epic bd-zxw6.

Commands:
  - plan:   resolve universe, gating, topo layers
  - run:    execute epics in parallel worktrees with bounded impl/review loop
  - status: show checkpoint summary
  - doctor: preflight checks (Beads, OpenCode, agents, git/gh)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import textwrap
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Any


# Allow imports from repo root (lib/*)
sys.path.insert(0, str(Path(__file__).parent.parent))


DEFAULT_OPENCODE_URL = os.environ.get("OPENCODE_URL", "http://127.0.0.1:4105").rstrip("/")
DEFAULT_MAX_PARALLEL = 3
DEFAULT_MAX_ATTEMPTS = 3


def _now_ts() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def log(msg: str, level: str = "INFO") -> None:
    print(f"[{_now_ts()}] [{level}] {msg}")


def die(msg: str, code: int = 2) -> None:
    print(f"dx-ralph: {msg}", file=sys.stderr)
    raise SystemExit(code)


def run_cmd(
    argv: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    timeout: int | None = None,
    check: bool = False,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        argv,
        cwd=str(cwd) if cwd else None,
        env=env,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=check,
    )


def read_text(path: Path, limit_bytes: int = 200_000) -> str:
    try:
        data = path.read_bytes()
        if len(data) > limit_bytes:
            data = data[:limit_bytes] + b"\n...<truncated>...\n"
        return data.decode("utf-8", errors="replace")
    except FileNotFoundError:
        return ""


def parse_repo_map(values: list[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for v in values:
        if "=" not in v:
            die(f"--repo-map expects bd-xxxx=repo, got: {v}")
        k, repo = v.split("=", 1)
        k = k.strip()
        repo = repo.strip()
        if not k or not repo:
            die(f"--repo-map expects bd-xxxx=repo, got: {v}")
        out[k] = repo
    return out


def ensure_beads_dir() -> str:
    beads_dir = os.environ.get("BEADS_DIR")
    if not beads_dir:
        die('BEADS_DIR is required (external Beads DB). Example: export BEADS_DIR="$HOME/bd/.beads"')
    return beads_dir


def bd_show(issue_id: str) -> dict[str, Any] | None:
    ensure_beads_dir()
    proc = run_cmd(["bd", "--no-daemon", "show", issue_id, "--json"], timeout=20)
    if proc.returncode != 0:
        return None
    try:
        data = json.loads(proc.stdout)
        if isinstance(data, list) and data:
            return data[0]
        return None
    except json.JSONDecodeError:
        return None


def bd_close(issue_id: str, reason: str) -> bool:
    ensure_beads_dir()
    proc = run_cmd(["bd", "--no-daemon", "close", issue_id, "--reason", reason], timeout=30)
    return proc.returncode == 0


def is_closed(status: str | None) -> bool:
    return (status or "").lower() == "closed"


def normalize_labels(labels: Any) -> list[str]:
    if not labels:
        return []
    if isinstance(labels, list):
        return [str(x) for x in labels if x is not None]
    return []


def has_label(labels: list[str], needle: str) -> bool:
    return needle in {l.strip() for l in labels}


def parse_repo_label(labels: list[str]) -> str | None:
    for l in labels:
        if l.startswith("repo:"):
            repo = l.split(":", 1)[1].strip()
            return repo or None
    return None


def extract_dependencies(issue: dict[str, Any]) -> list[dict[str, str]]:
    deps = issue.get("dependencies") or []
    if not isinstance(deps, list):
        return []
    out: list[dict[str, str]] = []
    for d in deps:
        if not isinstance(d, dict):
            continue
        depends_on = d.get("depends_on_id") or d.get("dependsOnID") or d.get("id")
        dep_type = d.get("type") or d.get("dependency_type") or d.get("dependencyType") or ""
        if depends_on:
            out.append({"id": str(depends_on), "type": str(dep_type)})
    return out


@dataclass
class EpicNode:
    id: str
    title: str
    description: str
    status: str
    issue_type: str
    labels: list[str]
    repo: str | None
    deps_all: list[str]  # all dependencies (any type)
    deps_epics: list[str]  # dependencies that are epics (subset, for topo edges)


@dataclass
class PlanEntry:
    id: str
    repo: str | None
    state: str  # runnable|skipped|blocked|done|needs_human
    reason: str
    deps: list[str]


def resolve_repo(issue: dict[str, Any], labels: list[str], repo_map: dict[str, str]) -> str | None:
    repo_field = issue.get("repo")
    if isinstance(repo_field, str) and repo_field.strip():
        return repo_field.strip()
    label_repo = parse_repo_label(labels)
    if label_repo:
        return label_repo
    issue_id = str(issue.get("id") or "")
    if issue_id and issue_id in repo_map:
        return repo_map[issue_id]
    return None


def fetch_universe_epics(root_ids: list[str], repo_map: dict[str, str]) -> tuple[dict[str, EpicNode], dict[str, str]]:
    """
    Returns:
      epics_by_id: all epics in dependency closure (including non-runnable)
      errors: issue_id -> error string for anything not fetched/invalid
    """
    epics: dict[str, EpicNode] = {}
    errors: dict[str, str] = {}
    to_fetch: list[str] = list(dict.fromkeys(root_ids))
    seen: set[str] = set()

    while to_fetch:
        issue_id = to_fetch.pop(0)
        if issue_id in seen:
            continue
        seen.add(issue_id)

        issue = bd_show(issue_id)
        if not issue:
            errors[issue_id] = "not found or invalid JSON"
            continue

        issue_type = str(issue.get("issue_type") or "")
        if issue_type != "epic":
            errors[issue_id] = f"not an epic (issue_type={issue_type})"
            continue

        labels = normalize_labels(issue.get("labels"))
        repo = resolve_repo(issue, labels, repo_map)

        deps_all = [d["id"] for d in extract_dependencies(issue)]
        for dep_id in deps_all:
            if dep_id and dep_id not in seen:
                to_fetch.append(dep_id)

        node = EpicNode(
            id=str(issue.get("id")),
            title=str(issue.get("title") or ""),
            description=str(issue.get("description") or ""),
            status=str(issue.get("status") or ""),
            issue_type=issue_type,
            labels=labels,
            repo=repo,
            deps_all=deps_all,
            deps_epics=[],
        )
        epics[node.id] = node

    # Second pass: classify deps as epic vs non-epic where possible.
    for epic in list(epics.values()):
        deps_epics: list[str] = []
        for dep_id in epic.deps_all:
            if dep_id in epics:
                deps_epics.append(dep_id)
        epic.deps_epics = deps_epics

    return epics, errors


def topo_layers(nodes: dict[str, EpicNode], runnable_ids: set[str]) -> tuple[list[list[str]], list[str]]:
    """Return layers and cycle_ids (subset of runnable_ids)."""
    incoming: dict[str, int] = {i: 0 for i in runnable_ids}
    outgoing: dict[str, list[str]] = {i: [] for i in runnable_ids}

    for epic_id in runnable_ids:
        for dep in nodes[epic_id].deps_epics:
            if dep in runnable_ids:
                incoming[epic_id] += 1
                outgoing.setdefault(dep, []).append(epic_id)

    ready = [i for i, c in incoming.items() if c == 0]
    layers: list[list[str]] = []
    processed: set[str] = set()

    while ready:
        layer = sorted(ready)
        layers.append(layer)
        new_ready: list[str] = []
        for n in layer:
            processed.add(n)
            for m in outgoing.get(n, []):
                incoming[m] -= 1
                if incoming[m] == 0:
                    new_ready.append(m)
        ready = new_ready

    cycle_ids = sorted([i for i in runnable_ids if i not in processed])
    return layers, cycle_ids


def compute_plan(
    root_ids: list[str],
    repo_map: dict[str, str],
) -> tuple[dict[str, EpicNode], dict[str, PlanEntry], list[list[str]], dict[str, str]]:
    nodes, errors = fetch_universe_epics(root_ids, repo_map)
    plan: dict[str, PlanEntry] = {}

    # Initial classification
    for epic_id, epic in nodes.items():
        if is_closed(epic.status):
            plan[epic_id] = PlanEntry(epic_id, epic.repo, "done", "already closed", epic.deps_all)
            continue
        if not has_label(epic.labels, "ralph-ready"):
            plan[epic_id] = PlanEntry(epic_id, epic.repo, "skipped", "missing label ralph-ready", epic.deps_all)
            continue
        if not epic.repo:
            plan[epic_id] = PlanEntry(epic_id, epic.repo, "skipped", "repo not resolved (need epic.repo or repo:<name> label or --repo-map)", epic.deps_all)
            continue
        plan[epic_id] = PlanEntry(epic_id, epic.repo, "runnable", "ok", epic.deps_all)

    # Block epics with unmet dependencies not in runnable set and not closed.
    changed = True
    while changed:
        changed = False
        runnable_ids = {i for i, p in plan.items() if p.state == "runnable"}
        for epic_id in sorted(runnable_ids):
            epic = nodes[epic_id]
            unmet: list[str] = []
            for dep_id in epic.deps_all:
                if dep_id in nodes:
                    if is_closed(nodes[dep_id].status):
                        continue
                    if plan.get(dep_id) and plan[dep_id].state == "runnable":
                        continue
                    unmet.append(dep_id)
                else:
                    dep_issue = bd_show(dep_id)
                    if dep_issue and is_closed(str(dep_issue.get("status") or "")):
                        continue
                    unmet.append(dep_id)
            if unmet:
                plan[epic_id] = PlanEntry(epic_id, epic.repo, "blocked", f"unmet dependencies: {', '.join(unmet)}", epic.deps_all)
                changed = True

    runnable_ids = {i for i, p in plan.items() if p.state == "runnable"}
    layers, cycles = topo_layers(nodes, runnable_ids)
    if cycles:
        for c in cycles:
            plan[c] = PlanEntry(c, nodes[c].repo, "blocked", "cycle detected in runnable subgraph", nodes[c].deps_all)
        runnable_ids = {i for i, p in plan.items() if p.state == "runnable"}
        layers, _ = topo_layers(nodes, runnable_ids)

    return nodes, plan, layers, errors


def checkpoint_default_path() -> Path:
    base = Path.home() / ".dx" / "ralph"
    base.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    return base / f"dx-ralph-{ts}.json"


@dataclass
class EpicRunState:
    id: str
    repo: str | None
    state: str
    attempts: int = 0
    last_signal: str | None = None
    last_reason: str | None = None
    worktree: str | None = None
    pr_url: str | None = None
    ci_lite_exit: int | None = None
    ci_lite_tail: str | None = None


@dataclass
class Checkpoint:
    version: int
    created_at: str
    opencode_url: str
    mode: str
    close_mode: str
    max_parallel: int
    max_attempts: int
    universe_roots: list[str]
    epics: dict[str, EpicRunState]


def write_checkpoint(path: Path, ckpt: Checkpoint) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    payload = asdict(ckpt)
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(path)


def load_checkpoint(path: Path) -> Checkpoint:
    data = json.loads(path.read_text(encoding="utf-8"))
    epics = {k: EpicRunState(**v) for k, v in (data.get("epics") or {}).items()}
    return Checkpoint(
        version=int(data.get("version") or 1),
        created_at=str(data.get("created_at") or ""),
        opencode_url=str(data.get("opencode_url") or DEFAULT_OPENCODE_URL),
        mode=str(data.get("mode") or "dev"),
        close_mode=str(data.get("close_mode") or "orchestrator"),
        max_parallel=int(data.get("max_parallel") or DEFAULT_MAX_PARALLEL),
        max_attempts=int(data.get("max_attempts") or DEFAULT_MAX_ATTEMPTS),
        universe_roots=list(data.get("universe_roots") or []),
        epics=epics,
    )


def status_table(ckpt: Checkpoint) -> str:
    rows = []
    for epic_id in sorted(ckpt.epics.keys()):
        e = ckpt.epics[epic_id]
        rows.append(
            [
                epic_id,
                e.repo or "-",
                e.state,
                str(e.attempts),
                (e.last_signal or "-")[:18],
                ("pass" if e.ci_lite_exit == 0 else ("fail" if e.ci_lite_exit else "-")),
                (e.pr_url or "-")[:32],
            ]
        )
    headers = ["epic", "repo", "state", "att", "signal", "ci", "pr"]
    widths = [max(len(r[i]) for r in ([headers] + rows)) for i in range(len(headers))]
    out_lines = []
    out_lines.append("  ".join(headers[i].ljust(widths[i]) for i in range(len(headers))))
    out_lines.append("  ".join("-" * widths[i] for i in range(len(headers))))
    for r in rows:
        out_lines.append("  ".join(r[i].ljust(widths[i]) for i in range(len(headers))))
    return "\n".join(out_lines)


def opencode_health(url: str) -> tuple[bool, str]:
    try:
        proc = run_cmd(["curl", "-s", f"{url}/global/health"], timeout=5)
        if proc.returncode != 0:
            return False, proc.stderr.strip() or "curl failed"
        data = json.loads(proc.stdout)
        if data.get("healthy") is True:
            return True, str(data.get("version") or "unknown")
        return False, "unhealthy"
    except Exception as e:
        return False, str(e)


def ensure_opencode_agents() -> list[str]:
    agents_dir = Path.home() / ".opencode" / "agents"
    missing: list[str] = []
    for name in ("ralph-implementer.json", "ralph-reviewer.json"):
        p = agents_dir / name
        if not p.exists():
            missing.append(str(p))
            continue
        try:
            json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            missing.append(str(p) + " (invalid JSON)")
    return missing


def detect_ci_lite(makefile: Path) -> bool:
    txt = read_text(makefile, limit_bytes=200_000)
    return bool(re.search(r"(?m)^ci-lite\s*:", txt))


def ci_lite_run(worktree: Path, timeout_sec: int = 1800) -> tuple[int, str]:
    proc = run_cmd(["make", "ci-lite"], cwd=worktree, timeout=timeout_sec)
    combined = (proc.stdout or "") + ("\n" + proc.stderr if proc.stderr else "")
    tail = "\n".join(combined.splitlines()[-80:])
    return proc.returncode, tail


def dx_worktree_create(epic_id: str, repo: str) -> Path:
    proc = run_cmd(["dx-worktree", "create", epic_id, repo], timeout=120)
    if proc.returncode != 0:
        die(f"dx-worktree create failed for {epic_id} {repo}: {proc.stderr.strip()}")
    path = (proc.stdout or "").strip().splitlines()[-1].strip()
    if not path:
        die("dx-worktree create returned empty path")
    p = Path(path)
    if not p.exists():
        die(f"worktree path does not exist: {path}")
    return p


def dx_worktree_cleanup(epic_id: str) -> None:
    run_cmd(["dx-worktree", "cleanup", epic_id], timeout=120)


def git_porcelain(worktree: Path) -> str:
    proc = run_cmd(["git", "status", "--porcelain=v1"], cwd=worktree, timeout=30)
    return proc.stdout or ""


def git_head(worktree: Path) -> str:
    proc = run_cmd(["git", "rev-parse", "HEAD"], cwd=worktree, timeout=10)
    return (proc.stdout or "").strip()


def git_commit_if_needed(worktree: Path, epic_id: str) -> bool:
    porcelain = git_porcelain(worktree).strip()
    if not porcelain:
        return False
    env = os.environ.copy()
    agent = env.get("DX_AGENT_ID") or env.get("USER") or "agent"
    title = f"chore({epic_id}): dx-ralph changes"
    body = f"Feature-Key: {epic_id}\nAgent: {agent}\nRole: dx-ralph\n"
    run_cmd(["git", "add", "-A"], cwd=worktree, timeout=60)
    proc = run_cmd(["git", "commit", "-m", title, "-m", body], cwd=worktree, timeout=60)
    return proc.returncode == 0


def gh_create_draft_pr(worktree: Path) -> str | None:
    if shutil.which("gh") is None:
        return None
    proc = run_cmd(["gh", "pr", "create", "--draft", "--fill"], cwd=worktree, timeout=120)
    out = (proc.stdout or "") + ("\n" + proc.stderr if proc.stderr else "")
    for line in out.splitlines():
        if "github.com" in line and "/pull/" in line:
            return line.strip()
    return None


def git_push(worktree: Path) -> bool:
    proc = run_cmd(["git", "push", "-u", "origin", "HEAD"], cwd=worktree, timeout=180)
    return proc.returncode == 0


def opencode_create_session(base_url: str, title: str) -> str:
    proc = run_cmd(
        ["curl", "-s", "-X", "POST", f"{base_url}/session", "-H", "Content-Type: application/json", "-d", json.dumps({"title": title})],
        timeout=10,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "failed to create session")
    data = json.loads(proc.stdout)
    sid = data.get("id")
    if not sid:
        raise RuntimeError("no session id returned")
    return str(sid)


def opencode_delete_session(base_url: str, session_id: str) -> None:
    run_cmd(["curl", "-s", "-X", "DELETE", f"{base_url}/session/{session_id}"], timeout=10)


def opencode_message(
    base_url: str,
    session_id: str,
    agent: str,
    model: dict[str, Any],
    prompt: str,
    timeout_sec: int,
) -> str:
    payload = {
        "agent": agent,
        "model": model,
        "parts": [{"type": "text", "text": prompt}],
    }
    proc = run_cmd(
        ["curl", "-s", "-X", "POST", f"{base_url}/session/{session_id}/message", "-H", "Content-Type: application/json", "-d", json.dumps(payload)],
        timeout=timeout_sec,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "message failed")
    data = json.loads(proc.stdout)
    parts = data.get("parts") or []
    texts: list[str] = []
    for p in parts:
        if isinstance(p, dict) and p.get("type") == "text":
            t = p.get("text")
            if isinstance(t, str) and t.strip():
                texts.append(t)
    out = "\n".join(texts).strip()
    return out or "ERROR: no text response"


SIGNAL_APPROVED = re.compile(r"(✅\s*APPROVED|\bAPPROVED\b)", re.IGNORECASE)
SIGNAL_REVISION = re.compile(r"(🔴\s*REVISION_REQUIRED|\bREVISION_REQUIRED\b)", re.IGNORECASE)


def parse_reviewer_signal(text: str) -> tuple[str, str]:
    if SIGNAL_APPROVED.search(text):
        return "APPROVED", text.strip().splitlines()[0][:240]
    if SIGNAL_REVISION.search(text):
        return "REVISION_REQUIRED", text.strip().splitlines()[0][:240]
    return "UNKNOWN", (text.strip().splitlines()[0][:240] if text.strip() else "empty reviewer output")


def constraints_prelude(worktree: Path, epic_id: str, repo: str) -> str:
    constraints_path = Path.home() / "agent-skills" / "dist" / "dx-global-constraints.md"
    return textwrap.dedent(
        f"""\
        EPIC: {epic_id}
        REPO: {repo}
        WORKTREE: {worktree}

        HARD RULES:
        - You MUST work only inside the WORKTREE above. Never edit canonical clones under ~/<repo>.
        - First commands:
            cd {worktree} && pwd
            cat {constraints_path}
            sed -n '1,200p' AGENTS.md
        - Use short, focused context. Do not carry context from other epics.
        """
    ).strip()


def build_impl_prompt(worktree: Path, epic: EpicNode, reviewer_feedback: str | None) -> str:
    fb = f"\nReviewer feedback to address:\n{reviewer_feedback}\n" if reviewer_feedback else ""
    return textwrap.dedent(
        f"""\
        {constraints_prelude(worktree, epic.id, epic.repo or "")}

        TASK:
        Implement Beads epic {epic.id}: {epic.title}

        Description:
        {epic.description}
        {fb}

        Output: IMPLEMENTATION_COMPLETE when you believe the epic is implemented.
        """
    ).strip()


def build_review_prompt(worktree: Path, epic: EpicNode, ci_tail: str | None) -> str:
    ci = f"\nci-lite output tail:\n{ci_tail}\n" if ci_tail else ""
    return textwrap.dedent(
        f"""\
        {constraints_prelude(worktree, epic.id, epic.repo or "")}

        REVIEW TASK:
        Review the implementation of Beads epic {epic.id}: {epic.title}

        Requirements:
        - Verify changes in git (status/diff) and ensure they satisfy the epic description.
        - If ci-lite output indicates failure, require revision.
        - Be lenient about trailing newlines.

        {ci}

        Output ONE line only:
        ✅ APPROVED: <reason>
        🔴 REVISION_REQUIRED: <specific issue>
        """
    ).strip()


def run_single_epic(
    base_url: str,
    epic: EpicNode,
    mode: str,
    close_mode: str,
    max_attempts: int,
    dry_run: bool,
    keep_worktrees: bool,
    ckpt: "Checkpoint",
    ckpt_path: Path,
) -> None:
    epic_state = ckpt.epics[epic.id]
    epic_state.state = "running"
    write_checkpoint(ckpt_path, ckpt)

    worktree = dx_worktree_create(epic.id, epic.repo or "")
    epic_state.worktree = str(worktree)
    write_checkpoint(ckpt_path, ckpt)

    impl_model = {"providerID": "zai-coding-plan", "modelID": "glm-4.7"}
    rev_model = {"providerID": "zai-coding-plan", "modelID": "glm-4.7"}
    if mode == "prod":
        rev_model = {"providerID": "openai", "modelID": "gpt-5.2", "variant": "high"}

    reviewer_feedback: str | None = None
    last_head = git_head(worktree)

    for attempt in range(1, max_attempts + 1):
        epic_state.attempts = attempt
        epic_state.state = "implementing"
        write_checkpoint(ckpt_path, ckpt)

        sid = opencode_create_session(base_url, f"dx-ralph-impl-{epic.id}-a{attempt}")
        try:
            impl_prompt = build_impl_prompt(worktree, epic, reviewer_feedback)
            _ = opencode_message(base_url, sid, "ralph-implementer", impl_model, impl_prompt, timeout_sec=600)
        finally:
            opencode_delete_session(base_url, sid)

        head_after = git_head(worktree)
        porcelain = git_porcelain(worktree).strip()
        if head_after == last_head and not porcelain:
            epic_state.state = "needs_human"
            epic_state.last_signal = "NO_PROGRESS"
            epic_state.last_reason = "No progress detected (HEAD unchanged and worktree clean)"
            write_checkpoint(ckpt_path, ckpt)
            return
        last_head = head_after

        makefile = worktree / "Makefile"
        ci_exit = None
        ci_tail = None
        if makefile.exists() and detect_ci_lite(makefile):
            epic_state.state = "verifying"
            write_checkpoint(ckpt_path, ckpt)
            ci_exit, ci_tail = ci_lite_run(worktree)
            epic_state.ci_lite_exit = ci_exit
            epic_state.ci_lite_tail = ci_tail
            write_checkpoint(ckpt_path, ckpt)

        epic_state.state = "reviewing"
        write_checkpoint(ckpt_path, ckpt)
        sid = opencode_create_session(base_url, f"dx-ralph-rev-{epic.id}-a{attempt}")
        try:
            review_prompt = build_review_prompt(worktree, epic, ci_tail)
            rev_text = opencode_message(base_url, sid, "ralph-reviewer", rev_model, review_prompt, timeout_sec=600)
        finally:
            opencode_delete_session(base_url, sid)

        signal, reason = parse_reviewer_signal(rev_text)
        epic_state.last_signal = signal
        epic_state.last_reason = reason
        write_checkpoint(ckpt_path, ckpt)

        if signal == "APPROVED":
            if ci_exit is not None and ci_exit != 0:
                reviewer_feedback = f"ci-lite failed (exit={ci_exit}). Fix failures before approval.\n{ci_tail}"
                continue
            epic_state.state = "approved"
            write_checkpoint(ckpt_path, ckpt)
            break

        if signal == "REVISION_REQUIRED":
            reviewer_feedback = rev_text
            continue

        epic_state.state = "needs_human"
        epic_state.last_signal = "UNKNOWN_REVIEW"
        epic_state.last_reason = f"Unknown reviewer signal: {reason}"
        write_checkpoint(ckpt_path, ckpt)
        return
    else:
        epic_state.state = "needs_human"
        epic_state.last_signal = "MAX_ATTEMPTS"
        epic_state.last_reason = f"Max attempts reached ({max_attempts})"
        write_checkpoint(ckpt_path, ckpt)
        return

    epic_state.state = "surfacing_pr"
    write_checkpoint(ckpt_path, ckpt)

    if dry_run:
        epic_state.pr_url = "DRY_RUN"
        epic_state.state = "done"
        write_checkpoint(ckpt_path, ckpt)
        if not keep_worktrees:
            dx_worktree_cleanup(epic.id)
        return

    _ = git_commit_if_needed(worktree, epic.id)
    if not git_push(worktree):
        epic_state.state = "needs_human"
        epic_state.last_signal = "PUSH_FAILED"
        epic_state.last_reason = "git push failed"
        write_checkpoint(ckpt_path, ckpt)
        return

    pr_url = gh_create_draft_pr(worktree)
    if not pr_url:
        epic_state.state = "needs_human"
        epic_state.last_signal = "PR_FAILED"
        epic_state.last_reason = "gh pr create failed (no PR URL captured)"
        write_checkpoint(ckpt_path, ckpt)
        return

    epic_state.pr_url = pr_url
    write_checkpoint(ckpt_path, ckpt)

    if close_mode == "orchestrator":
        epic_state.state = "closing"
        write_checkpoint(ckpt_path, ckpt)
        reason = f"dx-ralph: {pr_url}"
        _ = bd_close(epic.id, reason)
        epic_json = bd_show(epic.id) or {}
        deps = epic_json.get("dependents") or []
        if isinstance(deps, list):
            for child in deps:
                if not isinstance(child, dict):
                    continue
                if child.get("dependency_type") != "parent-child":
                    continue
                child_id = child.get("id")
                child_status = str(child.get("status") or "")
                if child_id and not is_closed(child_status):
                    bd_close(str(child_id), f"Closed with parent epic {epic.id}")

    epic_state.state = "done"
    write_checkpoint(ckpt_path, ckpt)

    if not keep_worktrees:
        dx_worktree_cleanup(epic.id)


def cmd_doctor(args: argparse.Namespace) -> int:
    ensure_beads_dir()
    if shutil.which("bd") is None:
        die("bd not found on PATH")
    if shutil.which("dx-worktree") is None:
        die("dx-worktree not found on PATH (run: ~/agent-skills/scripts/dx-ensure-bins.sh)")
    ok, ver = opencode_health(args.opencode_url)
    if not ok:
        die(f"OpenCode unhealthy at {args.opencode_url}: {ver}")
    missing_agents = ensure_opencode_agents()
    if missing_agents:
        die("Missing/invalid OpenCode agents: " + ", ".join(missing_agents))
    if shutil.which("git") is None:
        die("git not found")
    if shutil.which("gh") is None:
        log("gh not found (PR creation will fail)", "WARN")
    log(f"Beads OK (BEADS_DIR={os.environ.get('BEADS_DIR')})")
    log(f"OpenCode OK ({args.opencode_url}, version={ver})")
    log("OpenCode agents OK (ralph-implementer, ralph-reviewer)")
    return 0


def cmd_plan(args: argparse.Namespace) -> int:
    repo_map = parse_repo_map(args.repo_map or [])
    nodes, plan, layers, errors = compute_plan(args.universe, repo_map)

    if errors:
        log("Universe fetch errors:", "WARN")
        for k, v in sorted(errors.items()):
            log(f"  {k}: {v}", "WARN")

    def dump(state: str) -> None:
        items = [p for p in plan.values() if p.state == state]
        if not items:
            return
        print(f"\n== {state.upper()} ({len(items)}) ==")
        for p in sorted(items, key=lambda x: x.id):
            repo = p.repo or "-"
            print(f"- {p.id} [{repo}]: {p.reason}")

    dump("runnable")
    dump("blocked")
    dump("skipped")
    dump("done")

    print("\n== LAYERS ==")
    for i, layer in enumerate(layers):
        print(f"Layer {i}: {' '.join(layer)}")

    return 0


def cmd_status(args: argparse.Namespace) -> int:
    ckpt_path = Path(args.checkpoint).expanduser()
    ckpt = load_checkpoint(ckpt_path)
    print(status_table(ckpt))
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    repo_map = parse_repo_map(args.repo_map or [])
    nodes, plan, layers, errors = compute_plan(args.universe, repo_map)

    ckpt_path = Path(args.checkpoint).expanduser() if args.checkpoint else checkpoint_default_path()
    if args.resume:
        ckpt_path = Path(args.resume).expanduser()
        ckpt = load_checkpoint(ckpt_path)
    else:
        ckpt = Checkpoint(
            version=1,
            created_at=_now_ts(),
            opencode_url=args.opencode_url,
            mode=args.mode,
            close_mode=args.close_mode,
            max_parallel=args.max_parallel,
            max_attempts=args.max_attempts,
            universe_roots=list(args.universe),
            epics={},
        )

    for epic_id, p in plan.items():
        if epic_id not in ckpt.epics:
            ckpt.epics[epic_id] = EpicRunState(id=epic_id, repo=p.repo, state=p.state)
        else:
            if p.repo and not ckpt.epics[epic_id].repo:
                ckpt.epics[epic_id].repo = p.repo

    write_checkpoint(ckpt_path, ckpt)
    log(f"Checkpoint: {ckpt_path}")

    if errors:
        log("Universe fetch errors present; see plan output for details", "WARN")

    runnable_ids = [p.id for p in plan.values() if p.state == "runnable"]
    if not runnable_ids:
        log("No runnable epics.", "WARN")
        return 0

    import concurrent.futures

    for layer_num, layer in enumerate(layers):
        if not layer:
            continue
        log(f"Layer {layer_num}: {len(layer)} epic(s)")
        todo = []
        for epic_id in layer:
            st = ckpt.epics.get(epic_id)
            if not st:
                continue
            if st.state in ("done",):
                continue
            if plan[epic_id].state != "runnable":
                continue
            todo.append(epic_id)

        if not todo:
            continue

        with concurrent.futures.ThreadPoolExecutor(max_workers=args.max_parallel) as ex:
            futs = []
            for epic_id in todo:
                epic = nodes[epic_id]
                futs.append(
                    ex.submit(
                        run_single_epic,
                        args.opencode_url,
                        epic,
                        args.mode,
                        args.close_mode,
                        args.max_attempts,
                        args.dry_run,
                        args.keep_worktrees,
                        ckpt,
                        ckpt_path,
                    )
                )
            for f in concurrent.futures.as_completed(futs):
                try:
                    f.result()
                except Exception as e:
                    log(f"Epic execution exception: {e}", "ERROR")

        write_checkpoint(ckpt_path, ckpt)
        print(status_table(ckpt))

    log("Run complete")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="dx-ralph", formatter_class=argparse.RawTextHelpFormatter)
    p.add_argument("--opencode-url", default=DEFAULT_OPENCODE_URL, help="OpenCode server base URL")
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_universe_flags(sp: argparse.ArgumentParser) -> None:
        sp.add_argument("--universe", nargs="+", required=True, help="Root epic IDs")
        sp.add_argument("--repo-map", action="append", default=[], help="Override repo mapping: bd-xxxx=repo-name (repeatable)")
        sp.add_argument("--max-parallel", type=int, default=DEFAULT_MAX_PARALLEL, help="Max concurrent epics")
        sp.add_argument("--mode", choices=["dev", "prod"], default="dev", help="Model mode")
        sp.add_argument("--max-attempts", type=int, default=DEFAULT_MAX_ATTEMPTS, help="Max implement/review attempts per epic")
        sp.add_argument("--close-mode", choices=["orchestrator", "reviewer"], default="orchestrator", help="Who closes Beads (default orchestrator)")

    sp_plan = sub.add_parser("plan", help="Resolve universe and print runnable/blocked/skipped + topo layers")
    add_universe_flags(sp_plan)
    sp_plan.set_defaults(func=cmd_plan)

    sp_run = sub.add_parser("run", help="Execute epics in worktrees with bounded parallelism")
    add_universe_flags(sp_run)
    sp_run.add_argument("--checkpoint", default=None, help="Checkpoint JSON path (default under ~/.dx/ralph/)")
    sp_run.add_argument("--resume", default=None, help="Resume from checkpoint JSON")
    sp_run.add_argument("--dry-run", action="store_true", help="Do not push/PR/close; still runs planning and loops")
    sp_run.add_argument("--keep-worktrees", action="store_true", help="Keep worktrees after run")
    sp_run.set_defaults(func=cmd_run)

    sp_status = sub.add_parser("status", help="Show checkpoint status table")
    sp_status.add_argument("--checkpoint", required=True, help="Checkpoint JSON path")
    sp_status.set_defaults(func=cmd_status)

    sp_doctor = sub.add_parser("doctor", help="Preflight checks for Beads/OpenCode/agents/git/gh")
    sp_doctor.set_defaults(func=cmd_doctor)

    return p


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args) or 0)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
