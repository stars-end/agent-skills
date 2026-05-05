#!/usr/bin/env python3
"""
dx-batch - Deterministic orchestration over dx-runner for autonomous implement->review waves
"""

from __future__ import annotations
import argparse, fcntl, json, os, re, shlex, shutil, signal, subprocess, sys, time, uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any, Optional

try:
    import jsonschema

    HAS_JSONSCHEMA = True
except ImportError:
    HAS_JSONSCHEMA = False

VERSION = "1.1.0"
DEFAULT_MAX_PARALLEL = 3
DEFAULT_MAX_ATTEMPTS = 3
DEFAULT_STALL_MINUTES = 15
DEFAULT_LEASE_TTL_MINUTES = 120
DEFAULT_EXEC_PROCESS_CAP = int(os.environ.get("DX_BATCH_EXEC_PROCESS_CAP", "60"))
DEFAULT_RETRY_CHAIN = ["opencode", "cc-glm", "blocked"]
ARTIFACT_BASE = Path("/tmp/dx-batch")
DX_RUNNER_LOG_BASE = Path("/tmp/dx-runner")
CONFIG_BASE = Path(__file__).parent.parent / "configs" / "dx-batch"
SCHEMAS_DIR = CONFIG_BASE / "schemas"
BEADS_RUNTIME_PATH = Path(
    os.environ.get("BEADS_DIR", str(Path.home() / ".beads-runtime" / ".beads"))
).expanduser()
BEADS_COMMAND_CWD = Path(
    os.environ.get("BEADS_REPO_PATH", str(BEADS_RUNTIME_PATH.parent))
).expanduser()
# Backward-compatible alias for older tests/plugins that monkeypatch the
# previous name while runtime code uses the clearer command-CWD constant.
BEADS_REPO_PATH = BEADS_COMMAND_CWD
BEADS_LOCK_FILE = BEADS_RUNTIME_PATH / ".dx-bd-mutation.lock"
MIN_BD_VERSION = os.environ.get("DX_MIN_BD_VERSION", "0.49.4")

CANONICAL_REPOS = [
    Path.home() / "agent-skills",
    Path.home() / "prime-radiant-ai",
    Path.home() / "affordabot",
    Path.home() / "llm-common",
    Path.home() / "bd-symphony",
]

WORKSPACE_BASE = Path("/tmp/agents")

ALLOWED_WORKSPACE_PREFIXES = [
    WORKSPACE_BASE,
    Path("/private/tmp/agents"),
    Path("/tmp/dx-runner"),
    Path("/private/tmp/dx-runner"),
    Path("/tmp/dxbench"),
    Path("/private/tmp/dxbench"),
    Path("/tmp/dxbench_epyc6"),
    Path("/private/tmp/dxbench_epyc6"),
]

WORKSPACE_VIOLATION_EXIT_CODE = 22


def is_canonical_repo_path(path: Path) -> bool:
    """Check if path is a canonical repo or descendant (bd-kuhj.3)."""
    try:
        resolved = path.resolve()
    except (OSError, RuntimeError):
        return False
    for canonical in CANONICAL_REPOS:
        try:
            canonical_resolved = canonical.resolve()
        except (OSError, RuntimeError):
            continue
        if resolved == canonical_resolved:
            return True
        try:
            resolved.relative_to(canonical_resolved)
            return True
        except ValueError:
            pass
    return False


def validate_workspace_path(path: Optional[Path]) -> tuple[bool, str, int]:
    """
    Validate that a workspace path is allowed for mutating operations.

    Returns (is_valid, reason_code, exit_code).
    - is_valid: True if path is allowed, False otherwise
    - reason_code: Human-readable reason
    - exit_code: Exit code to use (0 for success, 22 for canonical rejection)
    """
    if path is None:
        return True, "no_workspace_path", 0

    try:
        resolved = path.resolve()
    except (OSError, RuntimeError):
        return True, "path_resolution_failed", 0

    # bd-kuhj.3: Reject canonical repo paths (workspace-first enforcement)
    if is_canonical_repo_path(path):
        return (
            False,
            f"canonical_worktree_forbidden:{resolved}",
            WORKSPACE_VIOLATION_EXIT_CODE,
        )

    # Check if path starts with any allowed prefix
    for prefix in ALLOWED_WORKSPACE_PREFIXES:
        try:
            prefix_resolved = prefix.resolve()
            resolved.relative_to(prefix_resolved)
            return True, "workspace_allowed", 0
        except (ValueError, OSError, RuntimeError):
            pass

    # Additional prefixes from environment
    extra_prefixes = os.environ.get("DX_RUNNER_EXTRA_ALLOWED_PREFIXES", "")
    if extra_prefixes:
        for extra in extra_prefixes.split(","):
            extra_path = Path(extra.strip()).expanduser()
            try:
                extra_resolved = extra_path.resolve()
                resolved.relative_to(extra_resolved)
                return True, "workspace_allowed_extra", 0
            except (ValueError, OSError, RuntimeError):
                pass

    return False, f"non_workspace_path:{resolved}", 1


def is_git_worktree_path(path: Path) -> bool:
    """Return True when path is a git repo/worktree root."""
    try:
        result = subprocess.run(
            ["git", "-C", str(path), "rev-parse", "--git-dir"],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return False
    return result.returncode == 0


def find_item_worktrees(beads_id: str) -> list[Path]:
    """Find direct git worktree children under /tmp/agents/<beads-id>/."""
    workspace_root = WORKSPACE_BASE / beads_id
    if not workspace_root.is_dir():
        return []

    candidates: list[Path] = []
    for child in sorted(workspace_root.iterdir()):
        if child.name.startswith(".") or not child.is_dir():
            continue
        if is_git_worktree_path(child):
            try:
                candidates.append(child.resolve())
            except (OSError, RuntimeError):
                candidates.append(child)
    return candidates


def resolve_item_worktree(beads_id: str) -> tuple[Optional[Path], str, int]:
    """Resolve the single real workspace for a dx-batch item."""
    candidates = find_item_worktrees(beads_id)
    workspace_root = WORKSPACE_BASE / beads_id

    if not candidates:
        return None, f"worktree_missing:{workspace_root}", 1

    if len(candidates) != 1:
        joined = ",".join(str(path) for path in candidates)
        return None, f"worktree_ambiguous:{joined}", 1

    worktree = candidates[0]
    is_valid, reason_code, exit_code = validate_workspace_path(worktree)
    if not is_valid:
        return None, reason_code, exit_code
    return worktree, "workspace_resolved", 0


class ItemStatus(str, Enum):
    PENDING = "pending"
    IMPLEMENTING = "implementing"
    REVIEWING = "reviewing"
    APPROVED = "approved"
    REVISION_REQUIRED = "revision_required"
    BLOCKED = "blocked"
    FAILED = "failed"
    CANCELLED = "cancelled"


class WaveStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    PAUSED = "paused"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class Phase(str, Enum):
    IMPLEMENT = "implement"
    REVIEW = "review"


class Verdict(str, Enum):
    APPROVED = "APPROVED"
    REVISION_REQUIRED = "REVISION_REQUIRED"
    BLOCKED = "BLOCKED"


@dataclass
class WaveConfig:
    max_parallel: int = DEFAULT_MAX_PARALLEL
    max_attempts: int = DEFAULT_MAX_ATTEMPTS
    retry_chain: list = field(default_factory=lambda: DEFAULT_RETRY_CHAIN.copy())
    stall_minutes: int = DEFAULT_STALL_MINUTES
    lease_ttl_minutes: int = DEFAULT_LEASE_TTL_MINUTES
    exec_process_cap: int = DEFAULT_EXEC_PROCESS_CAP
    require_review: bool = True


@dataclass
class ItemState:
    beads_id: str
    status: ItemStatus = ItemStatus.PENDING
    attempt: int = 1
    provider: Optional[str] = None
    run_instance: Optional[str] = None
    lease_key: Optional[str] = None
    phase: Optional[Phase] = None
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    verdict: Optional[Verdict] = None
    outcome_path: Optional[str] = None
    error: Optional[str] = None
    reason_code: Optional[str] = None
    dx_runner_beads_id: Optional[str] = (
        None  # The actual beads ID passed to dx-runner (may have -review suffix)
    )

    def to_dict(self):
        d = asdict(self)
        d["status"] = self.status.value
        if self.phase:
            d["phase"] = self.phase.value
        if self.verdict:
            d["verdict"] = self.verdict.value
        return {k: v for k, v in d.items() if v is not None}

    @classmethod
    def from_dict(cls, d):
        if "status" in d and isinstance(d["status"], str):
            d["status"] = ItemStatus(d["status"])
        if "phase" in d and isinstance(d["phase"], str):
            d["phase"] = Phase(d["phase"])
        if "verdict" in d and isinstance(d["verdict"], str):
            d["verdict"] = Verdict(d["verdict"])
        return cls(**{k: v for k, v in d.items() if k in cls.__dataclass_fields__})


@dataclass
class WaveStats:
    total: int = 0
    pending: int = 0
    implementing: int = 0
    reviewing: int = 0
    approved: int = 0
    revision_required: int = 0
    blocked: int = 0
    failed: int = 0
    cancelled: int = 0


@dataclass
class WaveState:
    wave_id: str
    status: WaveStatus = WaveStatus.PENDING
    items: list = field(default_factory=list)
    config: WaveConfig = field(default_factory=WaveConfig)
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    stats: Optional[WaveStats] = None
    error: Optional[str] = None
    reason_code: Optional[str] = None

    def to_dict(self):
        return {
            "wave_id": self.wave_id,
            "status": self.status.value,
            "items": [i.to_dict() for i in self.items],
            "config": asdict(self.config),
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
            "stats": asdict(self.stats) if self.stats else None,
            "error": self.error,
            "reason_code": self.reason_code,
        }

    @classmethod
    def from_dict(cls, d):
        items = [ItemState.from_dict(i) for i in d.get("items", [])]
        config_data = d.get("config", {})
        config = WaveConfig(
            **{
                k: v
                for k, v in config_data.items()
                if k in WaveConfig.__dataclass_fields__
            }
        )
        stats = WaveStats(**d["stats"]) if d.get("stats") else None
        return cls(
            wave_id=d["wave_id"],
            status=WaveStatus(d["status"])
            if isinstance(d.get("status"), str)
            else WaveStatus.PENDING,
            items=items,
            config=config,
            created_at=d.get("created_at"),
            updated_at=d.get("updated_at"),
            started_at=d.get("started_at"),
            completed_at=d.get("completed_at"),
            stats=stats,
            error=d.get("error"),
            reason_code=d.get("reason_code"),
        )

    def compute_stats(self):
        stats = WaveStats(total=len(self.items))
        for item in self.items:
            if item.status == ItemStatus.PENDING:
                stats.pending += 1
            elif item.status == ItemStatus.IMPLEMENTING:
                stats.implementing += 1
            elif item.status == ItemStatus.REVIEWING:
                stats.reviewing += 1
            elif item.status == ItemStatus.APPROVED:
                stats.approved += 1
            elif item.status == ItemStatus.REVISION_REQUIRED:
                stats.revision_required += 1
            elif item.status == ItemStatus.BLOCKED:
                stats.blocked += 1
            elif item.status == ItemStatus.FAILED:
                stats.failed += 1
            elif item.status == ItemStatus.CANCELLED:
                stats.cancelled += 1
        self.stats = stats
        return stats


class LeaseLock:
    def __init__(
        self, wave_id, beads_id, attempt, ttl_minutes=DEFAULT_LEASE_TTL_MINUTES
    ):
        self.wave_id, self.beads_id, self.attempt, self.ttl_minutes = (
            wave_id,
            beads_id,
            attempt,
            ttl_minutes,
        )
        self.lease_dir = ARTIFACT_BASE / "leases" / wave_id
        self.lease_key = f"{beads_id}+attempt{attempt}"
        self.lease_file = self.lease_dir / f"{self.lease_key}.lock"
        self._fd = None

    def acquire(self):
        self.lease_dir.mkdir(parents=True, exist_ok=True)
        try:
            self._fd = os.open(str(self.lease_file), os.O_CREAT | os.O_RDWR, 0o644)
            fcntl.flock(self._fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            os.write(
                self._fd,
                json.dumps(
                    {
                        "wave_id": self.wave_id,
                        "beads_id": self.beads_id,
                        "attempt": self.attempt,
                        "acquired_at": now_utc(),
                        "pid": os.getpid(),
                        "ttl_minutes": self.ttl_minutes,
                    }
                ).encode(),
            )
            return True
        except (BlockingIOError, OSError):
            if self._fd is not None:
                os.close(self._fd)
                self._fd = None
            return False

    def release(self):
        if self._fd is not None:
            try:
                fcntl.flock(self._fd, fcntl.LOCK_UN)
                os.close(self._fd)
            except OSError:
                pass
            self._fd = None
        try:
            self.lease_file.unlink(missing_ok=True)
        except OSError:
            pass

    def is_stale(self):
        if not self.lease_file.exists():
            return True
        try:
            data = json.loads(self.lease_file.read_text())
            acquired_at = data.get("acquired_at", "")
            if acquired_at:
                if (time.time() - parse_utc_epoch(acquired_at)) > data.get(
                    "ttl_minutes", self.ttl_minutes
                ) * 60:
                    return True
        except (json.JSONDecodeError, OSError):
            return True
        return False

    def force_release_if_stale(self):
        if self.is_stale():
            try:
                self.lease_file.unlink()
            except OSError:
                pass
            return True
        return False

    @classmethod
    def list_stale_leases(cls, wave_id, ttl_minutes=DEFAULT_LEASE_TTL_MINUTES):
        lease_dir = ARTIFACT_BASE / "leases" / wave_id
        if not lease_dir.exists():
            return []
        stale = []
        for lock_file in lease_dir.glob("*.lock"):
            try:
                data = json.loads(lock_file.read_text())
                if (
                    data.get("acquired_at")
                    and (time.time() - parse_utc_epoch(data["acquired_at"]))
                    > data.get("ttl_minutes", ttl_minutes) * 60
                ):
                    stale.append({"file": str(lock_file), **data})
            except (json.JSONDecodeError, OSError):
                stale.append({"file": str(lock_file), "error": "corrupt"})
        return stale


class Ledger:
    def __init__(self, wave_id, beads_id):
        self.wave_id, self.beads_id = wave_id, beads_id
        self.ledger_dir = ARTIFACT_BASE / "ledgers" / wave_id
        self.ledger_file = self.ledger_dir / f"{beads_id}.ledger.jsonl"

    def _ensure_dir(self):
        self.ledger_dir.mkdir(parents=True, exist_ok=True)

    def append_run(self, record):
        self._ensure_dir()
        for f in [
            "provider",
            "run_instance",
            "attempt",
            "state",
            "started_at",
            "outcome_path",
        ]:
            if f not in record:
                raise ValueError(f"Missing required field: {f}")
        record["recorded_at"] = now_utc()
        with open(self.ledger_file, "a") as f:
            f.write(json.dumps(record) + "\n")

    def get_latest_run(self):
        if not self.ledger_file.exists():
            return None
        latest = None
        with open(self.ledger_file) as f:
            for line in f:
                line = line.strip()
                if line:
                    latest = json.loads(line)
        return latest

    def get_all_runs(self):
        if not self.ledger_file.exists():
            return []
        runs = []
        with open(self.ledger_file) as f:
            for line in f:
                line = line.strip()
                if line:
                    runs.append(json.loads(line))
        return runs

    def get_attempt_count(self):
        return len(self.get_all_runs())


class ContractValidator:
    def __init__(self):
        self.implement_schema = self._load_schema("implement_contract.json")
        self.review_schema = self._load_schema("review_contract.json")

    def _load_schema(self, name):
        schema_path = SCHEMAS_DIR / name
        if schema_path.exists():
            return json.loads(schema_path.read_text())
        return None

    def validate_implement(self, contract):
        if not HAS_JSONSCHEMA or not self.implement_schema:
            return self._validate_implement_basic(contract)
        try:
            jsonschema.validate(contract, self.implement_schema)
            return True, []
        except jsonschema.ValidationError as e:
            return False, [str(e)]

    def validate_review(self, contract):
        if not HAS_JSONSCHEMA or not self.review_schema:
            return self._validate_review_basic(contract)
        try:
            jsonschema.validate(contract, self.review_schema)
            if contract.get("verdict") in (
                "REVISION_REQUIRED",
                "BLOCKED",
            ) and not contract.get("findings"):
                return False, [
                    "findings required when verdict is REVISION_REQUIRED or BLOCKED"
                ]
            return True, []
        except jsonschema.ValidationError as e:
            return False, [str(e)]

    def _validate_implement_basic(self, contract):
        errors = []
        if contract.get("phase") != "implement":
            errors.append("phase must be 'implement'")
        for f in ["beads_id", "status", "artifacts", "timestamp"]:
            if f not in contract:
                errors.append(f"{f} required")
        return len(errors) == 0, errors

    def _validate_review_basic(self, contract):
        errors = []
        if contract.get("phase") != "review":
            errors.append("phase must be 'review'")
        if "beads_id" not in contract:
            errors.append("beads_id required")
        if contract.get("verdict") not in ("APPROVED", "REVISION_REQUIRED", "BLOCKED"):
            errors.append("verdict must be APPROVED, REVISION_REQUIRED, or BLOCKED")
        if "findings" not in contract:
            errors.append("findings required")
        if contract.get("verdict") in (
            "REVISION_REQUIRED",
            "BLOCKED",
        ) and not contract.get("findings"):
            errors.append(
                "findings required when verdict is REVISION_REQUIRED or BLOCKED"
            )
        if "timestamp" not in contract:
            errors.append("timestamp required")
        return len(errors) == 0, errors


class PreflightChecker:
    def __init__(self, retry_chain):
        self.retry_chain, self.results = retry_chain, {}

    def run(self):
        all_passed = True
        for provider in self.retry_chain:
            if provider == "blocked":
                continue
            result = self._check_provider(provider)
            self.results[provider] = result
            if not result.get("available", False):
                all_passed = False
        return all_passed, self.results

    def _check_provider(self, provider):
        result = {
            "provider": provider,
            "available": False,
            "error": None,
            "reason_code": None,
            "checked_at": now_utc(),
        }
        try:
            proc = subprocess.run(
                ["dx-runner", "preflight", "--provider", provider],
                capture_output=True,
                text=True,
                timeout=60,
            )
            combined_output = "\n".join(
                [proc.stdout.strip(), proc.stderr.strip()]
            ).strip()
            if proc.returncode == 0:
                result["available"] = True
            else:
                reason = "preflight_failed"
                for line in combined_output.splitlines():
                    if "reason_code=" in line:
                        reason = line.split("reason_code=", 1)[1].strip()
                        break
                result["error"], result["reason_code"] = (
                    combined_output,
                    normalize_reason_code(reason, "preflight_failed"),
                )
        except subprocess.TimeoutExpired:
            result["error"], result["reason_code"] = (
                "Preflight check timed out",
                "preflight_timeout",
            )
        except FileNotFoundError:
            result["error"], result["reason_code"] = (
                "dx-runner not found in PATH",
                "dx_runner_missing",
            )
        except Exception as e:
            result["error"], result["reason_code"] = str(e), "unknown_error"
        return result

    def get_first_available_provider(self):
        for provider in self.retry_chain:
            if provider != "blocked" and self.results.get(provider, {}).get(
                "available", False
            ):
                return provider
        return None


class RetryPolicy:
    def __init__(self, retry_chain=None, max_attempts=DEFAULT_MAX_ATTEMPTS):
        self.retry_chain = retry_chain or DEFAULT_RETRY_CHAIN.copy()
        self.max_attempts = max_attempts

    def get_provider_for_attempt(
        self, attempt, previous_provider=None, previous_error=None
    ):
        if attempt > self.max_attempts:
            return "blocked", "max_attempts_exceeded"
        chain_index = min(attempt - 1, len(self.retry_chain) - 1)
        provider = self.retry_chain[chain_index]
        if provider == "blocked":
            return "blocked", "retry_chain_exhausted"
        return (
            provider,
            "primary" if chain_index == 0 else f"fallback_from_{previous_provider}",
        )

    def is_terminal(self, provider):
        return provider == "blocked"

    def should_retry(self, attempt, error=None):
        return attempt < self.max_attempts


class ProcessHygiene:
    def __init__(self, max_parallel=DEFAULT_MAX_PARALLEL, wave_id=""):
        self.max_parallel, self.wave_id, self.child_pids = max_parallel, wave_id, set()
        self.jobs_dir = ARTIFACT_BASE / "jobs" / wave_id if wave_id else None

    def can_start_new(self):
        self._prune_dead_pids()
        return len(self.child_pids) < self.max_parallel

    def register_pid(self, pid):
        self.child_pids.add(pid)
        if self.jobs_dir:
            self.jobs_dir.mkdir(parents=True, exist_ok=True)
            (self.jobs_dir / f"{pid}.pid").write_text(
                json.dumps(
                    {"pid": pid, "registered_at": now_utc(), "wave_id": self.wave_id}
                )
            )

    def unregister_pid(self, pid):
        self.child_pids.discard(pid)
        if self.jobs_dir:
            (self.jobs_dir / f"{pid}.pid").unlink(missing_ok=True)

    def _prune_dead_pids(self):
        dead = {pid for pid in self.child_pids if not self._is_pid_alive(pid)}
        for pid in dead:
            self.unregister_pid(pid)
        return len(dead)

    def _is_pid_alive(self, pid):
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False

    def kill_all_children(self, exclude_pids=None):
        exclude_pids = exclude_pids or set()
        killed = 0
        for pid in list(self.child_pids):
            if pid in exclude_pids:
                continue
            try:
                os.kill(pid, signal.SIGTERM)
                killed += 1
            except OSError:
                pass
        deadline = time.time() + 10
        while time.time() < deadline and self.child_pids:
            self._prune_dead_pids()
            if not self.child_pids:
                break
            time.sleep(0.5)
        for pid in list(self.child_pids):
            if pid in exclude_pids:
                continue
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        self._prune_dead_pids()
        return killed

    def prune_stale_pids(self):
        pruned = []
        if self.jobs_dir and self.jobs_dir.exists():
            for pid_file in self.jobs_dir.glob("*.pid"):
                try:
                    data = json.loads(pid_file.read_text())
                    if data.get("pid") and not self._is_pid_alive(data["pid"]):
                        pid_file.unlink()
                        pruned.append(data["pid"])
                except (json.JSONDecodeError, OSError):
                    pid_file.unlink(missing_ok=True)
        return pruned

    @staticmethod
    def _read_pid_file(pid_file):
        try:
            content = pid_file.read_text().strip()
        except OSError:
            return None
        if not content:
            return None
        if content.startswith("{"):
            try:
                data = json.loads(content)
            except json.JSONDecodeError:
                return None
            pid = data.get("pid")
            if isinstance(pid, int) and pid > 0:
                return pid
            return None
        try:
            pid = int(content.splitlines()[0].strip())
            return pid if pid > 0 else None
        except ValueError:
            return None

    def count_live_external_processes(self):
        live_pids = set()
        for pid in self.child_pids:
            if self._is_pid_alive(pid):
                live_pids.add(pid)

        pid_files = []
        if DX_RUNNER_LOG_BASE.exists():
            pid_files.extend(DX_RUNNER_LOG_BASE.glob("*/*.pid"))
        jobs_root = ARTIFACT_BASE / "jobs"
        if jobs_root.exists():
            pid_files.extend(jobs_root.glob("*/*.pid"))

        for pid_file in pid_files:
            pid = self._read_pid_file(pid_file)
            if pid and self._is_pid_alive(pid):
                live_pids.add(pid)
        return len(live_pids), sorted(live_pids)


class ArtifactManager:
    def __init__(self, wave_id):
        self.wave_id = wave_id
        self.base = ARTIFACT_BASE / "waves" / wave_id

    def get_wave_dir(self):
        return self.base

    def get_state_file(self):
        return self.base / "wave_state.json"

    def get_outcome_dir(self):
        return self.base / "outcomes"

    def get_log_dir(self):
        return self.base / "logs"

    def get_item_outcome_path(self, beads_id, phase, attempt):
        return (
            self.get_outcome_dir()
            / f"{beads_id}.{phase.value}.attempt{attempt}.outcome.json"
        )

    def get_item_log_path(self, beads_id, phase, attempt):
        return self.get_log_dir() / f"{beads_id}.{phase.value}.attempt{attempt}.log"

    def ensure_dirs(self):
        self.base.mkdir(parents=True, exist_ok=True)
        self.get_outcome_dir().mkdir(parents=True, exist_ok=True)
        self.get_log_dir().mkdir(parents=True, exist_ok=True)

    def write_outcome(self, beads_id, phase, attempt, outcome):
        self.ensure_dirs()
        path = self.get_item_outcome_path(beads_id, phase, attempt)
        if "timestamp" not in outcome:
            outcome["timestamp"] = now_utc()
        outcome["artifact_path"] = str(path)
        path.write_text(json.dumps(outcome, indent=2))
        return path

    def write_timeout_outcome(self, beads_id, phase, attempt, reason):
        return self.write_outcome(
            beads_id,
            phase,
            attempt,
            {
                "phase": phase.value,
                "beads_id": beads_id,
                "attempt": attempt,
                "status": "timeout",
                "error": reason,
            },
        )

    def write_cancel_outcome(self, beads_id, phase, attempt, reason):
        return self.write_outcome(
            beads_id,
            phase,
            attempt,
            {
                "phase": phase.value,
                "beads_id": beads_id,
                "attempt": attempt,
                "status": "cancelled",
                "error": reason,
            },
        )

    def write_error_outcome(self, beads_id, phase, attempt, error):
        return self.write_outcome(
            beads_id,
            phase,
            attempt,
            {
                "phase": phase.value,
                "beads_id": beads_id,
                "attempt": attempt,
                "status": "error",
                "error": error,
            },
        )


def now_utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize_reason_code(value: Optional[str], default: str) -> str:
    if not value:
        return default
    return value.strip().lower().replace(" ", "_")


def derive_wave_reason_code(state: WaveState) -> str:
    if state.reason_code:
        return normalize_reason_code(state.reason_code, "wave_unknown")
    if state.status == WaveStatus.PENDING:
        return "wave_pending"
    if state.status == WaveStatus.RUNNING:
        return "wave_running"
    if state.status == WaveStatus.PAUSED:
        return "wave_paused"
    if state.status == WaveStatus.COMPLETED:
        return "wave_completed"
    if state.status == WaveStatus.CANCELLED:
        return "wave_cancelled"
    if state.status == WaveStatus.FAILED:
        return "wave_failed"
    return "wave_unknown"


def derive_item_reason_code(item: ItemState) -> str:
    if item.reason_code:
        return normalize_reason_code(item.reason_code, "unknown")
    if item.status == ItemStatus.APPROVED:
        return "approved"
    if item.status == ItemStatus.BLOCKED:
        return "blocked"
    if item.status == ItemStatus.REVISION_REQUIRED:
        return "revision_required"
    if item.status == ItemStatus.FAILED:
        return "failed"
    if item.status == ItemStatus.CANCELLED:
        return "cancelled"
    if item.status == ItemStatus.IMPLEMENTING:
        return "implementing"
    if item.status == ItemStatus.REVIEWING:
        return "reviewing"
    return "pending"


def derive_wave_next_action(state: WaveState) -> str:
    if state.status == WaveStatus.RUNNING:
        return "monitor_wave_until_terminal"
    if state.status == WaveStatus.PAUSED:
        return "run_dx_batch_resume"
    if state.status == WaveStatus.FAILED:
        reason = derive_wave_reason_code(state)
        if reason.startswith("exec_saturation"):
            return "run_dx_runner_prune_then_dx_batch_doctor"
        if reason.startswith("doctor_critical"):
            return "run_dx_batch_doctor_and_resolve_critical"
        return "inspect_wave_error_and_recover"
    if state.status == WaveStatus.CANCELLED:
        return "review_outcomes_before_restart"
    if state.status == WaveStatus.COMPLETED:
        return "review_report_and_close_items"
    return "start_or_resume_wave"


def parse_utc_epoch(ts):
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def _parse_semver(version: str) -> tuple:
    cleaned = (version or "").strip().split("-", 1)[0]
    parts = cleaned.split(".")
    nums = []
    for part in parts[:3]:
        try:
            nums.append(int(part))
        except ValueError:
            nums.append(0)
    while len(nums) < 3:
        nums.append(0)
    return tuple(nums)


def _check_bd_version() -> tuple[bool, str]:
    try:
        result = subprocess.run(
            ["bd", "--version"], capture_output=True, text=True, timeout=10
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as exc:
        return False, f"bd_version_check_failed:{exc}"

    if result.returncode != 0:
        msg = result.stderr.strip() or result.stdout.strip() or "unknown"
        return False, f"bd_version_command_failed:{msg}"

    match = re.search(r"\d+\.\d+\.\d+", result.stdout)
    version = match.group(0) if match else ""
    if _parse_semver(version) < _parse_semver(MIN_BD_VERSION):
        return False, f"bd_version_too_old:{version}<min:{MIN_BD_VERSION}"
    return True, version


def ensure_canonical_beads_cwd() -> tuple[bool, str]:
    if os.environ.get("DX_ALLOW_NON_CANONICAL_BD_CWD", "0").lower() in (
        "1",
        "true",
        "yes",
    ):
        return True, ""
    required = BEADS_RUNTIME_PATH.resolve()
    if not required.exists():
        return False, f"beads_runtime_missing:{required}"
    if not (required / "metadata.json").exists():
        return False, f"beads_runtime_metadata_missing:{required / 'metadata.json'}"
    return True, ""


def get_dx_runner_log_path(provider, beads_id):
    """Get the path to dx-runner's provider log file."""
    return DX_RUNNER_LOG_BASE / provider / f"{beads_id}.log"


def read_dx_runner_log(provider, beads_id):
    """Read dx-runner's provider log file content."""
    log_path = get_dx_runner_log_path(provider, beads_id)
    if not log_path.exists():
        return None
    try:
        return log_path.read_text()
    except OSError:
        return None


def bd_command(args, check=False):
    """Run a bd command. Returns (success, stdout, stderr)."""
    BEADS_LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    try:
        with open(BEADS_LOCK_FILE, "a+", encoding="utf-8") as lockf:
            fcntl.flock(lockf.fileno(), fcntl.LOCK_EX)
            result = subprocess.run(
                ["bd"] + args,
                cwd=str(BEADS_COMMAND_CWD),
                capture_output=True,
                text=True,
                timeout=60,
            )
        if check and result.returncode != 0:
            return False, result.stdout, result.stderr
        return result.returncode == 0, result.stdout, result.stderr
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return False, "", str(e)


class WaveOrchestrator:
    def __init__(self, wave_id, config=None):
        self.wave_id = wave_id
        self.config = config or WaveConfig()
        self.artifacts = ArtifactManager(wave_id)
        self.state = None
        self.hygiene = ProcessHygiene(self.config.max_parallel, wave_id)
        self.validator = ContractValidator()
        self.retry_policy = RetryPolicy(
            self.config.retry_chain, self.config.max_attempts
        )
        self._leases = {}  # Track active leases by beads_id+attempt for cleanup
        self._shutdown_requested = False
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

    def _signal_handler(self, signum, frame):
        self._shutdown_requested = True

    def load_state(self):
        state_file = self.artifacts.get_state_file()
        if state_file.exists():
            self.state = WaveState.from_dict(json.loads(state_file.read_text()))
        else:
            self.state = WaveState(
                wave_id=self.wave_id, config=self.config, created_at=now_utc()
            )
        return self.state

    def save_state(self):
        if self.state:
            self.state.updated_at = now_utc()
            self.state.compute_stats()
            self.artifacts.ensure_dirs()
            state_file = self.artifacts.get_state_file()
            tmp_file = state_file.with_suffix(".tmp")
            tmp_file.write_text(json.dumps(self.state.to_dict(), indent=2))
            tmp_file.rename(state_file)

    def create_wave(self, beads_ids):
        self.state = WaveState(
            wave_id=self.wave_id,
            status=WaveStatus.PENDING,
            items=[ItemState(beads_id=bid) for bid in beads_ids],
            config=self.config,
            created_at=now_utc(),
        )
        self.state.compute_stats()
        self.save_state()
        return self.state

    def start(self):
        self.load_state()
        if self.state.status == WaveStatus.COMPLETED:
            self.state.reason_code = "wave_completed"
            return True
        if self.state.status == WaveStatus.RUNNING:
            print(f"Wave {self.wave_id} already running", file=sys.stderr)
            self.state.reason_code = "wave_already_running"
            return False
        preflight = PreflightChecker(self.config.retry_chain)
        all_passed, results = preflight.run()
        if not all_passed:
            provider = preflight.get_first_available_provider()
            if not provider:
                self.state.status, self.state.error = (
                    WaveStatus.FAILED,
                    "No providers available",
                )
                self.state.reason_code = "no_provider_available"
                self.save_state()
                return False
            self.state.reason_code = "preflight_degraded"
            print(f"Warning: Some preflight checks failed. Using {provider}")
        self._run_runner_prune()
        if not self._enforce_exec_process_cap():
            self.save_state()
            return False
        self.state.status, self.state.started_at = WaveStatus.RUNNING, now_utc()
        self.state.reason_code = "wave_running"
        self.save_state()
        try:
            return self._run_loop()
        except Exception as e:
            self.state.status, self.state.error = WaveStatus.FAILED, str(e)
            self.state.reason_code = "orchestrator_exception"
            self.save_state()
            return False

    def _run_loop(self):
        while not self._shutdown_requested:
            self.load_state()
            if self.state.status != WaveStatus.RUNNING:
                break
            active_count = 0
            for item in self.state.items:
                if item.status in (ItemStatus.IMPLEMENTING, ItemStatus.REVIEWING):
                    active_count += 1
                    self._check_item_progress(item)
            if not self._run_dispatch_cycle_checks():
                if self.state.status != WaveStatus.RUNNING:
                    continue
            while (
                self.hygiene.can_start_new() and active_count < self.config.max_parallel
            ):
                item = self._get_next_item()
                if not item:
                    break
                if self._start_item(item):
                    active_count += 1
            if self._is_wave_complete():
                self.state.status, self.state.completed_at = (
                    WaveStatus.COMPLETED,
                    now_utc(),
                )
                self.state.reason_code = "wave_completed"
                self.save_state()
                return True
            time.sleep(5)
        if self._shutdown_requested:
            self.state.status = WaveStatus.PAUSED
            self.state.reason_code = "wave_paused_signal"
            self.save_state()
            self._cleanup_on_shutdown()
        return False

    def _run_runner_prune(self):
        try:
            subprocess.run(
                ["dx-runner", "prune", "--json"],
                capture_output=True,
                text=True,
                timeout=60,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            # Prune is best-effort; preflight/cap checks still protect dispatch.
            pass

    def _enforce_exec_process_cap(self):
        cap = max(1, int(self.config.exec_process_cap))
        live_count, _ = self.hygiene.count_live_external_processes()
        if live_count > cap:
            self.state.status = WaveStatus.FAILED
            self.state.reason_code = "exec_saturation"
            self.state.error = (
                f"exec_saturation: live_processes={live_count} cap={cap}; "
                "run dx-runner prune and dx-batch doctor before retrying"
            )
            print(
                (
                    f"Exec saturation guard triggered: live_processes={live_count} "
                    f"cap={cap}. Refusing new dispatches."
                ),
                file=sys.stderr,
            )
            return False
        return True

    def _run_dispatch_cycle_checks(self):
        # Keep doctor active every cycle before launching any new items.
        doctor_result = Doctor(self.wave_id).diagnose()
        critical_issues = [
            issue
            for issue in doctor_result.get("issues", [])
            if issue.get("severity") == "critical"
        ]
        if critical_issues:
            first = critical_issues[0]
            self.state.status = WaveStatus.FAILED
            self.state.reason_code = f"doctor_critical_{first.get('type', 'unknown')}"
            self.state.error = (
                f"doctor_critical:{first.get('type', 'unknown')} "
                f"{first.get('message', '')}".strip()
            )
            self.save_state()
            return False
        if not self._enforce_exec_process_cap():
            self.save_state()
            return False
        return True

    def _get_next_item(self):
        for item in self.state.items:
            if item.status == ItemStatus.PENDING:
                return item
            if (
                item.status == ItemStatus.REVISION_REQUIRED
                and item.attempt < self.config.max_attempts
            ):
                return item
        return None

    def _start_item(self, item):
        if item.status == ItemStatus.REVISION_REQUIRED:
            item.attempt += 1
        provider, reason = self.retry_policy.get_provider_for_attempt(
            item.attempt, item.provider, item.error
        )
        if provider == "blocked":
            item.status, item.error = ItemStatus.BLOCKED, "Retry chain exhausted"
            item.reason_code = "retry_chain_exhausted"
            phase = item.phase or Phase.IMPLEMENT
            self.artifacts.write_error_outcome(
                item.beads_id, phase, item.attempt, "Retry chain exhausted"
            )
            self.save_state()
            return False
        lease = LeaseLock(
            self.wave_id, item.beads_id, item.attempt, self.config.lease_ttl_minutes
        )
        if not lease.acquire():
            if not lease.force_release_if_stale() or not lease.acquire():
                print(
                    f"Could not acquire lease for {item.beads_id} attempt {item.attempt}",
                    file=sys.stderr,
                )
                return False
        # Track lease for cleanup
        self._leases[f"{item.beads_id}+attempt{item.attempt}"] = lease

        item.provider, item.phase, item.status, item.lease_key = (
            provider,
            Phase.IMPLEMENT,
            ItemStatus.IMPLEMENTING,
            lease.lease_key,
        )
        item.started_at, item.run_instance, item.dx_runner_beads_id = (
            now_utc(),
            f"{provider}-{uuid.uuid4().hex[:8]}",
            item.beads_id,
        )
        self.save_state()

        outcome_path = str(
            self.artifacts.get_item_outcome_path(
                item.beads_id, Phase.IMPLEMENT, item.attempt
            )
        )
        item.outcome_path = outcome_path
        ledger = Ledger(self.wave_id, item.beads_id)
        ledger.append_run(
            {
                "provider": provider,
                "run_instance": item.run_instance,
                "attempt": item.attempt,
                "state": "implementing",
                "started_at": item.started_at,
                "outcome_path": outcome_path,
            }
        )
        self._dispatch_implement(item)
        return True

    def _dispatch_implement(self, item):
        # bd-kuhj.3: Workspace-first gate - resolve the actual mutating worktree
        # and pass it explicitly to dx-runner instead of relying on cwd/prompt ancestry.

        cwd_path = Path.cwd()
        if is_canonical_repo_path(cwd_path):
            item.status, item.error = (
                ItemStatus.FAILED,
                f"Cannot dispatch from canonical repo: {cwd_path}",
            )
            item.reason_code = f"canonical_cwd_forbidden:{cwd_path}"
            self.artifacts.write_error_outcome(
                item.beads_id,
                Phase.IMPLEMENT,
                item.attempt,
                f"canonical_cwd_forbidden: dispatch attempted from {cwd_path}",
            )
            self._release_lease(item)
            self.save_state()
            print(
                f"ERROR: {item.beads_id} blocked: dispatch from canonical cwd {cwd_path}",
                file=sys.stderr,
            )
            print(
                f"Remedy: cd /tmp/agents && dx-batch start ...",
                file=sys.stderr,
            )
            return

        worktree_path, reason_code, _ = resolve_item_worktree(item.beads_id)
        if worktree_path is None:
            item.status, item.error = (
                ItemStatus.FAILED,
                f"Workspace resolution failed: {reason_code}",
            )
            item.reason_code = reason_code
            self.artifacts.write_error_outcome(
                item.beads_id,
                Phase.IMPLEMENT,
                item.attempt,
                f"workspace_resolution_failed: {reason_code}",
            )
            self._release_lease(item)
            self.save_state()
            print(
                f"ERROR: {item.beads_id} blocked: {reason_code}",
                file=sys.stderr,
            )
            if reason_code.startswith("worktree_missing:"):
                print(
                    f"Remedy: dx-worktree create {item.beads_id} <repo>",
                    file=sys.stderr,
                )
            elif reason_code.startswith("worktree_ambiguous:"):
                print(
                    f"Remedy: keep exactly one git worktree under {WORKSPACE_BASE / item.beads_id}",
                    file=sys.stderr,
                )
            else:
                print(
                    f"Remedy: move the item workspace under /tmp/agents/{item.beads_id}/<repo>",
                    file=sys.stderr,
                )
            return

        prompt = self._generate_implement_prompt(item)
        prompt_file = ARTIFACT_BASE / "prompts" / f"{item.beads_id}.implement.prompt"
        prompt_file.parent.mkdir(parents=True, exist_ok=True)

        prompt_file.write_text(prompt)
        cmd = [
            "dx-runner",
            "start",
            "--beads",
            item.dx_runner_beads_id,
            "--provider",
            item.provider,
            "--worktree",
            str(worktree_path),
            "--prompt-file",
            str(prompt_file),
        ]
        try:
            proc = subprocess.Popen(
                cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            self.hygiene.register_pid(proc.pid)
        except Exception as e:
            item.status, item.error = ItemStatus.FAILED, str(e)
            item.reason_code = "dispatch_failed"
            self.artifacts.write_error_outcome(
                item.beads_id, Phase.IMPLEMENT, item.attempt, str(e)
            )
            self._release_lease(item)
            self.save_state()

    def _generate_implement_prompt(self, item):
        return f"""Implement the task for Beads issue {item.beads_id}.
You are in the IMPLEMENT phase of a dx-batch wave.
Requirements:
1. Implement the task completely
2. Write tests if applicable
3. Commit changes with Feature-Key: {item.beads_id}
4. Output a JSON contract at the end with this structure:
{{"phase": "implement", "beads_id": "{item.beads_id}", "status": "completed|partial|failed|no_op|blocked",
  "artifacts": {{"files_changed": [], "commits": [], "tests_passed": true}}, "summary": "...", "timestamp": "{now_utc()}"}}
Write this contract as the LAST line of your output, prefixed with CONTRACT:JSON:"""

    def _check_item_progress(self, item):
        # Use the actual beads ID passed to dx-runner
        beads_to_check = item.dx_runner_beads_id or item.beads_id
        try:
            result = subprocess.run(
                ["dx-runner", "check", "--beads", beads_to_check, "--json"],
                capture_output=True,
                text=True,
                timeout=30,
            )
            # Handle both zero and non-zero return codes
            data = {}
            if result.stdout.strip():
                try:
                    data = json.loads(result.stdout)
                except json.JSONDecodeError:
                    pass

            state = data.get("state", "unknown")

            # Return code 0 with exited state means completion
            if result.returncode == 0 and state in ("exited_ok", "exited_err"):
                self._handle_item_completion(item, data)
            # Return code 2 means stalled
            elif result.returncode == 2 or state == "stalled":
                self._handle_item_stalled(item, data)
            # Return code 3 means error
            elif result.returncode == 3 or state in ("exited_err", "blocked"):
                self._handle_item_stalled(item, data)
            # Check for no_op state
            elif state == "no_op":
                self._handle_item_stalled(item, {"reason_code": "no_op"})
        except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
            pass

    def _handle_item_completion(self, item, check_data):
        if item.phase == Phase.IMPLEMENT:
            outcome = self._parse_implement_outcome(item)
            if outcome and outcome.get("status") in ("completed", "partial"):
                # Update ledger with completion
                self._update_ledger_completion(
                    item, Phase.IMPLEMENT, "completed", outcome
                )
                # Write outcome and update state
                outcome_path = self.artifacts.write_outcome(
                    item.beads_id, Phase.IMPLEMENT, item.attempt, outcome
                )
                item.outcome_path = str(outcome_path)
                # Release lease
                self._release_lease(item)
                if self.config.require_review:
                    item.reason_code = "implement_completed_pending_review"
                    self._start_review(item)
                else:
                    item.status, item.completed_at = ItemStatus.APPROVED, now_utc()
                    item.reason_code = "approved_no_review"
                    self._update_beads_progress(item)
            else:
                error_msg = (
                    outcome.get("error", "Implement failed")
                    if outcome
                    else "No outcome"
                )
                item.status, item.error, item.completed_at = (
                    ItemStatus.FAILED,
                    error_msg,
                    now_utc(),
                )
                item.reason_code = "implement_contract_missing_or_invalid"
                self.artifacts.write_error_outcome(
                    item.beads_id, Phase.IMPLEMENT, item.attempt, error_msg
                )
                self._update_ledger_completion(item, Phase.IMPLEMENT, "failed", outcome)
                self._release_lease(item)
            self.save_state()
        elif item.phase == Phase.REVIEW:
            outcome = self._parse_review_outcome(item)
            if outcome:
                verdict = outcome.get("verdict", "BLOCKED")
                item.verdict = Verdict(verdict)
                if verdict == "APPROVED":
                    item.status = ItemStatus.APPROVED
                    item.reason_code = "approved"
                elif verdict == "REVISION_REQUIRED":
                    item.status = ItemStatus.REVISION_REQUIRED
                    item.reason_code = "revision_required"
                else:
                    item.status = ItemStatus.BLOCKED
                    item.reason_code = "blocked"
                item.completed_at = now_utc()
                # Update ledger
                self._update_ledger_completion(
                    item, Phase.REVIEW, verdict.lower(), outcome
                )
                # Write outcome
                outcome_path = self.artifacts.write_outcome(
                    item.beads_id, Phase.REVIEW, item.attempt, outcome
                )
                item.outcome_path = str(outcome_path)
                # Release lease
                self._release_lease(item)
                # Update Beads
                self._update_beads_progress(item)
            else:
                item.status, item.error = ItemStatus.FAILED, "No review outcome"
                item.reason_code = "review_contract_missing_or_invalid"
                self._update_ledger_completion(item, Phase.REVIEW, "failed", None)
                self._release_lease(item)
            self.save_state()

    def _release_lease(self, item):
        """Release the lease for an item."""
        key = f"{item.beads_id}+attempt{item.attempt}"
        if key in self._leases:
            try:
                self._leases[key].release()
            except Exception:
                pass
            del self._leases[key]

    def _update_ledger_completion(self, item, phase, state, outcome):
        """Append a completion record to the ledger."""
        ledger = Ledger(self.wave_id, item.beads_id)
        record = {
            "provider": item.provider,
            "run_instance": item.run_instance,
            "attempt": item.attempt,
            "phase": phase.value,
            "state": state,
            "reason_code": derive_item_reason_code(item),
            "started_at": item.started_at,
            "completed_at": now_utc(),
            "outcome_path": item.outcome_path or "",
        }
        if outcome:
            record["outcome_summary"] = (
                outcome.get("summary", "") if isinstance(outcome, dict) else ""
            )
        ledger.append_run(record)

    def _update_beads_progress(self, item):
        """Update Beads issue with progress."""
        if item.status == ItemStatus.APPROVED:
            success, _, _ = bd_command(
                [
                    "note",
                    item.beads_id,
                    "--message",
                    f"dx-batch: completed with verdict {item.verdict.value if item.verdict else 'N/A'}",
                ]
            )
            if not success:
                # Non-blocking - just log
                pass
        elif item.status == ItemStatus.BLOCKED:
            success, _, _ = bd_command(
                [
                    "note",
                    item.beads_id,
                    "--message",
                    f"dx-batch: blocked - {item.error or 'unknown'}",
                ]
            )
        elif item.status == ItemStatus.REVISION_REQUIRED:
            success, _, _ = bd_command(
                [
                    "note",
                    item.beads_id,
                    "--message",
                    f"dx-batch: revision required - {item.error or 'see review findings'}",
                ]
            )

    def _parse_implement_outcome(self, item):
        # Read from dx-runner's provider log, not our launcher log
        if not item.provider:
            return {"status": "failed", "error": "No provider set"}
        log_content = read_dx_runner_log(
            item.provider, item.dx_runner_beads_id or item.beads_id
        )
        if not log_content:
            return {"status": "failed", "error": "No dx-runner log found"}
        for line in reversed(log_content.split("\n")):
            if "CONTRACT:JSON:" in line:
                try:
                    contract = json.loads(line.split("CONTRACT:JSON:", 1)[1].strip())
                    valid, errors = self.validator.validate_implement(contract)
                    if valid:
                        return contract
                except json.JSONDecodeError:
                    pass
        return {"status": "failed", "error": "No valid contract found"}

    def _parse_review_outcome(self, item):
        # Read from dx-runner's provider log
        provider = item.provider or "opencode"  # review uses primary provider
        review_beads_id = f"{item.beads_id}-review"
        log_content = read_dx_runner_log(provider, review_beads_id)
        if not log_content:
            return {
                "verdict": "BLOCKED",
                "findings": [
                    {"type": "error", "message": "No dx-runner log found for review"}
                ],
            }
        for line in reversed(log_content.split("\n")):
            if "CONTRACT:JSON:" in line:
                try:
                    contract = json.loads(line.split("CONTRACT:JSON:", 1)[1].strip())
                    valid, errors = self.validator.validate_review(contract)
                    if valid:
                        return contract
                except json.JSONDecodeError:
                    pass
        return {
            "verdict": "BLOCKED",
            "findings": [
                {"type": "error", "message": "No valid review contract found"}
            ],
        }

    def _start_review(self, item):
        # bd-kuhj.3: Resolve the same real worktree for review dispatch.
        worktree_path, reason_code, _ = resolve_item_worktree(item.beads_id)
        if worktree_path is None:
            item.phase, item.status = Phase.REVIEW, ItemStatus.FAILED
            item.error = f"Workspace validation failed for review: {reason_code}"
            item.reason_code = reason_code
            item.completed_at = now_utc()
            self.artifacts.write_error_outcome(
                item.beads_id,
                Phase.REVIEW,
                item.attempt,
                f"review_workspace_resolution_failed: {reason_code}",
            )
            self._release_lease(item)
            self.save_state()
            print(
                f"ERROR: {item.beads_id} review blocked: {reason_code}",
                file=sys.stderr,
            )
            if reason_code.startswith("worktree_missing:"):
                print(
                    f"Remedy: dx-worktree create {item.beads_id} <repo>",
                    file=sys.stderr,
                )
            elif reason_code.startswith("worktree_ambiguous:"):
                print(
                    f"Remedy: keep exactly one git worktree under {WORKSPACE_BASE / item.beads_id}",
                    file=sys.stderr,
                )
            return

        item.phase, item.status, item.started_at = (
            Phase.REVIEW,
            ItemStatus.REVIEWING,
            now_utc(),
        )
        # Set dx_runner_beads_id for review phase
        item.dx_runner_beads_id = f"{item.beads_id}-review"
        self.save_state()

        prompt = self._generate_review_prompt(item)
        prompt_file = ARTIFACT_BASE / "prompts" / f"{item.beads_id}.review.prompt"
        prompt_file.parent.mkdir(parents=True, exist_ok=True)
        prompt_file.write_text(prompt)

        provider, _ = self.retry_policy.get_provider_for_attempt(1)
        item.provider = provider
        review_run_instance = f"{provider}-review-{uuid.uuid4().hex[:8]}"
        item.run_instance = review_run_instance

        # Append to ledger for review start
        outcome_path = str(
            self.artifacts.get_item_outcome_path(
                item.beads_id, Phase.REVIEW, item.attempt
            )
        )
        item.outcome_path = outcome_path
        ledger = Ledger(self.wave_id, item.beads_id)
        ledger.append_run(
            {
                "provider": provider,
                "run_instance": review_run_instance,
                "attempt": item.attempt,
                "phase": "review",
                "state": "reviewing",
                "started_at": item.started_at,
                "outcome_path": outcome_path,
            }
        )

        cmd = [
            "dx-runner",
            "start",
            "--beads",
            item.dx_runner_beads_id,
            "--provider",
            provider,
            "--worktree",
            str(worktree_path),
            "--prompt-file",
            str(prompt_file),
        ]
        try:
            proc = subprocess.Popen(
                cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            self.hygiene.register_pid(proc.pid)
        except Exception as e:
            item.status, item.error = ItemStatus.FAILED, f"Review dispatch failed: {e}"
            item.reason_code = "review_dispatch_failed"
            self.artifacts.write_error_outcome(
                item.beads_id,
                Phase.REVIEW,
                item.attempt,
                f"Review dispatch failed: {e}",
            )
            self._release_lease(item)
            self.save_state()

    def _generate_review_prompt(self, item):
        return f"""Review the implementation for Beads issue {item.beads_id}.
You are in the REVIEW phase of a dx-batch wave.
Verdict must be one of: APPROVED, REVISION_REQUIRED, BLOCKED
Output a JSON contract with this EXACT structure:
{{"phase": "review", "beads_id": "{item.beads_id}", "verdict": "APPROVED|REVISION_REQUIRED|BLOCKED",
  "findings": [{{"type": "critical|major|minor|suggestion|positive", "message": "..."}}], "summary": "...", "timestamp": "{now_utc()}"}}
CRITICAL: If verdict is REVISION_REQUIRED or BLOCKED, you MUST include at least one finding.
Write this contract as the LAST line of your output, prefixed with CONTRACT:JSON:"""

    def _handle_item_stalled(self, item, check_data):
        reason = check_data.get("reason_code", "stalled")
        item.reason_code = normalize_reason_code(reason, "stalled")
        if self.retry_policy.should_retry(item.attempt):
            item.status, item.error = (
                ItemStatus.REVISION_REQUIRED,
                reason,
            )
        else:
            item.status, item.error = (
                ItemStatus.BLOCKED,
                "Stalled and max retries exceeded",
            )
        phase = item.phase or Phase.IMPLEMENT
        self.artifacts.write_timeout_outcome(item.beads_id, phase, item.attempt, reason)
        self._release_lease(item)
        self._update_beads_progress(item)
        self.save_state()

    def _is_wave_complete(self):
        return all(
            item.status
            in (
                ItemStatus.APPROVED,
                ItemStatus.BLOCKED,
                ItemStatus.CANCELLED,
                ItemStatus.FAILED,
            )
            for item in self.state.items
        )

    def _cleanup_on_shutdown(self):
        # Get current process PID to exclude from kill
        my_pid = os.getpid()
        self.hygiene.kill_all_children(exclude_pids={my_pid})
        # Release all leases
        for key, lease in list(self._leases.items()):
            try:
                lease.release()
            except Exception:
                pass
        self._leases.clear()

    def cancel(self):
        self.load_state()
        if self.state.status not in (WaveStatus.RUNNING, WaveStatus.PAUSED):
            return False
        self._cleanup_on_shutdown()
        for item in self.state.items:
            if item.status not in (
                ItemStatus.APPROVED,
                ItemStatus.BLOCKED,
                ItemStatus.CANCELLED,
                ItemStatus.FAILED,
            ):
                item.status, item.completed_at = ItemStatus.CANCELLED, now_utc()
                self.artifacts.write_cancel_outcome(
                    item.beads_id,
                    item.phase or Phase.IMPLEMENT,
                    item.attempt,
                    "wave_cancelled",
                )
                self._release_lease(item)
        self.state.status, self.state.completed_at = WaveStatus.CANCELLED, now_utc()
        self.state.reason_code = "wave_cancelled"
        self.save_state()
        return True

    def resume(self):
        self.load_state()
        if self.state.status != WaveStatus.PAUSED:
            print(
                f"Wave {self.wave_id} is not paused (status: {self.state.status.value})",
                file=sys.stderr,
            )
            return False
        self.state.status = WaveStatus.RUNNING
        self.state.reason_code = "wave_running"
        self.save_state()
        return self._run_loop()


class Doctor:
    def __init__(self, wave_id):
        self.wave_id = wave_id
        self.artifacts = ArtifactManager(wave_id)

    def diagnose(self):
        result = {
            "wave_id": self.wave_id,
            "checked_at": now_utc(),
            "issues": [],
            "recommendations": [],
        }
        state_file = self.artifacts.get_state_file()
        if not state_file.exists():
            result["issues"].append(
                {
                    "type": "missing_state",
                    "severity": "critical",
                    "message": "Wave state file not found",
                }
            )
            result["recommendations"].append("Wave may not exist or was deleted")
            return result
        state = WaveState.from_dict(json.loads(state_file.read_text()))
        result["status"] = state.status.value

        cwd_ok, cwd_msg = ensure_canonical_beads_cwd()
        if not cwd_ok:
            result["issues"].append(
                {
                    "type": "beads_non_canonical_cwd",
                    "severity": "critical",
                    "message": cwd_msg,
                }
            )

        ver_ok, ver_detail = _check_bd_version()
        if not ver_ok:
            result["issues"].append(
                {
                    "type": "bd_version_out_of_policy",
                    "severity": "critical",
                    "message": ver_detail,
                }
            )

        legacy_db = BEADS_RUNTIME_PATH / "beads.db"
        canonical_db = BEADS_RUNTIME_PATH / "bd.db"
        if legacy_db.exists() and canonical_db.exists():
            result["issues"].append(
                {
                    "type": "beads_db_ambiguity",
                    "severity": "critical",
                    "message": f"Both DB files exist: {legacy_db} and {canonical_db}",
                }
            )

        for lease in LeaseLock.list_stale_leases(self.wave_id):
            result["issues"].append(
                {
                    "type": "stale_lease",
                    "severity": "warning",
                    "beads_id": lease.get("beads_id"),
                    "message": f"Stale lease for {lease.get('beads_id')}",
                }
            )
        if LeaseLock.list_stale_leases(self.wave_id):
            result["recommendations"].append(
                f"Run 'dx-batch resume --wave-id {self.wave_id}' to recover"
            )
        for item in state.items:
            if item.status in (ItemStatus.IMPLEMENTING, ItemStatus.REVIEWING):
                # Check for missing outcome file
                if item.outcome_path and not Path(item.outcome_path).exists():
                    result["issues"].append(
                        {
                            "type": "missing_outcome",
                            "severity": "warning",
                            "beads_id": item.beads_id,
                            "phase": item.phase.value if item.phase else None,
                            "message": f"Missing outcome for {item.beads_id}",
                        }
                    )
                # Also check if dx-runner log exists
                if item.provider and item.dx_runner_beads_id:
                    log_path = get_dx_runner_log_path(
                        item.provider, item.dx_runner_beads_id
                    )
                    if not log_path.exists():
                        result["issues"].append(
                            {
                                "type": "missing_dx_runner_log",
                                "severity": "warning",
                                "beads_id": item.beads_id,
                                "provider": item.provider,
                                "message": f"No dx-runner log for {item.beads_id}",
                            }
                        )
        stuck_items = [
            i
            for i in state.items
            if i.status in (ItemStatus.IMPLEMENTING, ItemStatus.REVIEWING)
        ]
        if stuck_items and state.status == WaveStatus.RUNNING:
            result["issues"].append(
                {
                    "type": "potential_stuck",
                    "severity": "info",
                    "count": len(stuck_items),
                    "message": f"{len(stuck_items)} items may be stuck in active state",
                }
            )
        hygiene = ProcessHygiene(wave_id=self.wave_id)
        pruned = hygiene.prune_stale_pids()
        if pruned:
            result["issues"].append(
                {
                    "type": "stale_pids_pruned",
                    "severity": "info",
                    "count": len(pruned),
                    "pids": pruned,
                }
            )
        return result


def cmd_start(args):
    cwd_ok, cwd_msg = ensure_canonical_beads_cwd()
    if not cwd_ok:
        print(cwd_msg, file=sys.stderr)
        return 1
    wave_id = args.wave_id or f"wave-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    items = args.items.split(",") if args.items else []
    if not items:
        print("Error: --items required", file=sys.stderr)
        return 1
    config = WaveConfig(
        max_parallel=args.max_parallel or DEFAULT_MAX_PARALLEL,
        max_attempts=args.max_attempts or DEFAULT_MAX_ATTEMPTS,
        stall_minutes=args.stall_minutes or DEFAULT_STALL_MINUTES,
        exec_process_cap=args.exec_process_cap or DEFAULT_EXEC_PROCESS_CAP,
        require_review=not args.no_review,
    )
    orchestrator = WaveOrchestrator(wave_id, config)
    orchestrator.create_wave(items)
    print(f"Starting wave {wave_id} with {len(items)} items")
    return 0 if orchestrator.start() else 1


def cmd_status(args):
    cwd_ok, cwd_msg = ensure_canonical_beads_cwd()
    if not cwd_ok:
        print(cwd_msg, file=sys.stderr)
        return 1
    wave_id = args.wave_id
    if not wave_id:
        print("Error: --wave-id required", file=sys.stderr)
        return 1
    state_file = ArtifactManager(wave_id).get_state_file()
    if not state_file.exists():
        print(f"Wave {wave_id} not found", file=sys.stderr)
        return 1
    state = WaveState.from_dict(json.loads(state_file.read_text()))
    state.compute_stats()
    wave_reason = derive_wave_reason_code(state)
    next_action = derive_wave_next_action(state)
    if args.json:
        payload = state.to_dict()
        payload["reason_code"] = wave_reason
        payload["next_action"] = next_action
        payload["items"] = [
            {**item.to_dict(), "reason_code": derive_item_reason_code(item)}
            for item in state.items
        ]
        print(json.dumps(payload, indent=2))
    else:
        print(f"Wave: {wave_id}")
        print(f"Status: {state.status.value}")
        print(f"Reason: {wave_reason}")
        print(f"Next Action: {next_action}")
        print(f"Items: {len(state.items)}")
        if state.stats:
            print(
                f"  Approved: {state.stats.approved}\n  Blocked: {state.stats.blocked}\n  Pending: {state.stats.pending}"
            )
    return 0


def cmd_check(args):
    cwd_ok, cwd_msg = ensure_canonical_beads_cwd()
    if not cwd_ok:
        print(cwd_msg, file=sys.stderr)
        return 1
    wave_id = args.wave_id
    if not wave_id:
        print("Error: --wave-id required", file=sys.stderr)
        return 1
    state_file = ArtifactManager(wave_id).get_state_file()
    if not state_file.exists():
        if args.json:
            print(
                json.dumps(
                    {
                        "wave_id": wave_id,
                        "state": "missing",
                        "reason_code": "wave_not_found",
                        "next_action": "create_or_verify_wave_id",
                    }
                )
            )
        else:
            print(f"wave {wave_id} missing reason_code=wave_not_found")
        return 3
    state = WaveState.from_dict(json.loads(state_file.read_text()))
    state.compute_stats()
    wave_reason = derive_wave_reason_code(state)
    next_action = derive_wave_next_action(state)
    if args.json:
        print(
            json.dumps(
                {
                    "wave_id": wave_id,
                    "state": state.status.value,
                    "reason_code": wave_reason,
                    "next_action": next_action,
                    "stats": asdict(state.stats) if state.stats else {},
                }
            )
        )
    else:
        print(
            f"wave={wave_id} state={state.status.value} reason_code={wave_reason} next_action={next_action}"
        )
    if state.status in (WaveStatus.FAILED, WaveStatus.CANCELLED):
        return 3
    if state.status == WaveStatus.PAUSED:
        return 2
    return 0


def cmd_resume(args):
    cwd_ok, cwd_msg = ensure_canonical_beads_cwd()
    if not cwd_ok:
        print(cwd_msg, file=sys.stderr)
        return 1
    wave_id = args.wave_id
    if not wave_id:
        print("Error: --wave-id required", file=sys.stderr)
        return 1
    state_file = ArtifactManager(wave_id).get_state_file()
    if not state_file.exists():
        print(f"Wave {wave_id} not found", file=sys.stderr)
        return 1
    state = WaveState.from_dict(json.loads(state_file.read_text()))
    orchestrator = WaveOrchestrator(wave_id, state.config)
    return 0 if orchestrator.resume() else 1


def cmd_cancel(args):
    cwd_ok, cwd_msg = ensure_canonical_beads_cwd()
    if not cwd_ok:
        print(cwd_msg, file=sys.stderr)
        return 1
    wave_id = args.wave_id
    if not wave_id:
        print("Error: --wave-id required", file=sys.stderr)
        return 1
    state_file = ArtifactManager(wave_id).get_state_file()
    if not state_file.exists():
        print(f"Wave {wave_id} not found", file=sys.stderr)
        return 1
    state = WaveState.from_dict(json.loads(state_file.read_text()))
    orchestrator = WaveOrchestrator(wave_id, state.config)
    return 0 if orchestrator.cancel() else 1


def cmd_doctor(args):
    cwd_ok, cwd_msg = ensure_canonical_beads_cwd()
    if not cwd_ok:
        print(cwd_msg, file=sys.stderr)
        return 1
    wave_id = args.wave_id
    if not wave_id:
        print("Error: --wave-id required", file=sys.stderr)
        return 1
    doctor = Doctor(wave_id)
    result = doctor.diagnose()
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"Doctor Report for Wave: {wave_id}\nChecked: {result['checked_at']}\n")
        if result.get("issues"):
            print("Issues Found:")
            for issue in result["issues"]:
                print(
                    f"  [{issue.get('severity', 'info').upper()}] {issue.get('type')}: {issue.get('message')}"
                )
        else:
            print("No issues found.")
        if result.get("recommendations"):
            print("\nRecommendations:")
            for rec in result["recommendations"]:
                print(f"  - {rec}")
    return 0 if not result.get("issues") else 1


def cmd_report(args):
    wave_id = args.wave_id
    if not wave_id:
        print("Error: --wave-id required", file=sys.stderr)
        return 1
    state_file = ArtifactManager(wave_id).get_state_file()
    if not state_file.exists():
        print(f"Wave {wave_id} not found", file=sys.stderr)
        return 1

    state = WaveState.from_dict(json.loads(state_file.read_text()))
    state.compute_stats()
    wave_reason = derive_wave_reason_code(state)
    next_action = derive_wave_next_action(state)

    items = []
    for item in state.items:
        items.append(
            {
                "beads_id": item.beads_id,
                "status": item.status.value,
                "reason_code": derive_item_reason_code(item),
                "attempt": item.attempt,
                "provider": item.provider,
                "phase": item.phase.value if item.phase else None,
                "verdict": item.verdict.value if item.verdict else None,
                "run_instance": item.run_instance,
                "outcome_path": item.outcome_path,
                "error": item.error,
                "started_at": item.started_at,
                "completed_at": item.completed_at,
            }
        )

    payload = {
        "wave_id": wave_id,
        "state": state.status.value,
        "reason_code": wave_reason,
        "next_action": next_action,
        "created_at": state.created_at,
        "started_at": state.started_at,
        "completed_at": state.completed_at,
        "stats": asdict(state.stats) if state.stats else {},
        "items": items,
    }

    if args.format == "json":
        print(json.dumps(payload, indent=2))
        return 0

    print(f"# dx-batch Report: {wave_id}")
    print("")
    print(f"- State: {state.status.value}")
    print(f"- Reason Code: {wave_reason}")
    print(f"- Next Action: {next_action}")
    print(f"- Created: {state.created_at or '-'}")
    print(f"- Started: {state.started_at or '-'}")
    print(f"- Completed: {state.completed_at or '-'}")
    print("")
    if state.stats:
        print("## Stats")
        print(f"- Total: {state.stats.total}")
        print(f"- Pending: {state.stats.pending}")
        print(f"- Implementing: {state.stats.implementing}")
        print(f"- Reviewing: {state.stats.reviewing}")
        print(f"- Approved: {state.stats.approved}")
        print(f"- Revision Required: {state.stats.revision_required}")
        print(f"- Blocked: {state.stats.blocked}")
        print(f"- Failed: {state.stats.failed}")
        print(f"- Cancelled: {state.stats.cancelled}")
        print("")
    print("## Items")
    for item in items:
        print(
            f"- {item['beads_id']}: status={item['status']} reason_code={item['reason_code']} attempt={item['attempt']} provider={item['provider'] or '-'} verdict={item['verdict'] or '-'}"
        )
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="dx-batch: Deterministic orchestration over dx-runner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--version", action="version", version=f"dx-batch {VERSION}")
    subparsers = parser.add_subparsers(dest="command", help="Commands")
    start_parser = subparsers.add_parser("start", help="Start a new wave")
    start_parser.add_argument(
        "--items", required=True, help="Comma-separated Beads IDs"
    )
    start_parser.add_argument(
        "--wave-id", help="Wave ID (auto-generated if not provided)"
    )
    start_parser.add_argument(
        "--max-parallel",
        type=int,
        default=DEFAULT_MAX_PARALLEL,
        help="Max parallel jobs",
    )
    start_parser.add_argument(
        "--max-attempts",
        type=int,
        default=DEFAULT_MAX_ATTEMPTS,
        help="Max attempts per item",
    )
    start_parser.add_argument(
        "--stall-minutes",
        type=int,
        default=DEFAULT_STALL_MINUTES,
        help="Stall threshold",
    )
    start_parser.add_argument(
        "--exec-process-cap",
        type=int,
        default=DEFAULT_EXEC_PROCESS_CAP,
        help="Hard cap for live dispatch/runner processes before refusing new wave dispatch",
    )
    start_parser.add_argument(
        "--no-review", action="store_true", help="Skip review phase"
    )
    start_parser.set_defaults(func=cmd_start)
    status_parser = subparsers.add_parser("status", help="Show wave status")
    status_parser.add_argument("--wave-id", required=True, help="Wave ID")
    status_parser.add_argument("--json", action="store_true", help="JSON output")
    status_parser.set_defaults(func=cmd_status)
    check_parser = subparsers.add_parser(
        "check", help="Check wave health (reason_code + next_action)"
    )
    check_parser.add_argument("--wave-id", required=True, help="Wave ID")
    check_parser.add_argument("--json", action="store_true", help="JSON output")
    check_parser.set_defaults(func=cmd_check)
    resume_parser = subparsers.add_parser("resume", help="Resume a paused wave")
    resume_parser.add_argument("--wave-id", required=True, help="Wave ID")
    resume_parser.set_defaults(func=cmd_resume)
    cancel_parser = subparsers.add_parser("cancel", help="Cancel a running wave")
    cancel_parser.add_argument("--wave-id", required=True, help="Wave ID")
    cancel_parser.set_defaults(func=cmd_cancel)
    report_parser = subparsers.add_parser("report", help="Generate wave report")
    report_parser.add_argument("--wave-id", required=True, help="Wave ID")
    report_parser.add_argument(
        "--format",
        choices=["json", "markdown"],
        default="json",
        help="Report format",
    )
    report_parser.set_defaults(func=cmd_report)
    doctor_parser = subparsers.add_parser("doctor", help="Diagnose wave issues")
    doctor_parser.add_argument("--wave-id", required=True, help="Wave ID")
    doctor_parser.add_argument("--json", action="store_true", help="JSON output")
    doctor_parser.set_defaults(func=cmd_doctor)
    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        return 1
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
