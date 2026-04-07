"""
dx-loop Beads integration for wave dependency advancement

Reuses Ralph's topological dependency layering (Kahn's algorithm)
from beads-parallel.sh lines 138-268, but uses dx-runner substrate
instead of curl sessions.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List, Set
import subprocess
import json
import os
from pathlib import Path


@dataclass
class BeadsTask:
    """Represents a Beads task with dependency metadata"""

    beads_id: str
    title: str
    description: str = ""
    repo: Optional[str] = None
    status: str = "open"
    dependencies: List[str] = field(default_factory=list)
    dependents: List[str] = field(default_factory=list)
    priority: int = 2
    details_loaded: bool = True
    detail_load_error: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "beads_id": self.beads_id,
            "title": self.title,
            "description": self.description,
            "repo": self.repo,
            "status": self.status,
            "dependencies": self.dependencies,
            "dependents": self.dependents,
            "priority": self.priority,
            "details_loaded": self.details_loaded,
            "detail_load_error": self.detail_load_error,
        }


@dataclass
class WaveReadiness:
    """Summarized readiness for the current wave frontier."""

    ready: List[str] = field(default_factory=list)
    waiting_on_dependencies: List[Dict[str, Any]] = field(default_factory=list)
    pending_tasks: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "ready": list(self.ready),
            "waiting_on_dependencies": list(self.waiting_on_dependencies),
            "pending_tasks": list(self.pending_tasks),
            "waiting_count": len(self.waiting_on_dependencies),
        }


class BeadsWaveManager:
    """
    Manages Beads wave execution with topological dependency ordering

    Reuses Ralph's Kahn's algorithm implementation for layer computation,
    but integrates with dx-runner substrate instead of curl sessions.
    """

    def __init__(
        self,
        beads_repo_path: Optional[Path] = None,
        default_repo: Optional[str] = None,
    ):
        self.beads_repo_path = beads_repo_path or Path.home() / "bd"
        self.default_repo = default_repo
        self.tasks: Dict[str, BeadsTask] = {}
        self.layers: List[List[str]] = []
        self.completed: Set[str] = set()
        self.dependency_status_cache: Dict[str, str] = {}
        self.dependency_metadata_cache: Dict[str, Dict[str, Any]] = {}

    @staticmethod
    def _is_terminal_dependency_status(status: Optional[str]) -> bool:
        """Return True when a Beads dependency status should count as satisfied."""
        if not status:
            return False
        return status.lower() in {"closed", "resolved", "completed", "done"}

    def _is_dependency_satisfied(self, dep_id: str) -> bool:
        """Check whether a dependency is satisfied via wave completion or Beads status."""
        if dep_id in self.completed:
            return True

        if dep_id in self.tasks:
            return self._is_terminal_dependency_status(self.tasks[dep_id].status)

        return self._is_terminal_dependency_status(
            self.dependency_status_cache.get(dep_id)
        )

    def get_dependency_metadata(self, dep_id: str) -> Dict[str, Any]:
        """Return cached metadata for a dependency if available."""
        return dict(self.dependency_metadata_cache.get(dep_id, {}))

    def _infer_repo_from_dependency_context(self, task: BeadsTask) -> Optional[str]:
        """Infer a task repo from unique dependency/sibling metadata when possible."""
        candidates: Set[str] = set()

        for dep_id in task.dependencies:
            dep_meta = self.dependency_metadata_cache.get(dep_id, {})
            dep_repo = dep_meta.get("repo")
            if dep_repo:
                candidates.add(dep_repo)
                continue

            dep_task = self.tasks.get(dep_id)
            if dep_task and dep_task.repo:
                candidates.add(dep_task.repo)

        if len(candidates) == 1:
            return next(iter(candidates))

        sibling_repos = {
            existing.repo
            for existing in self.tasks.values()
            if existing.repo and existing.beads_id != task.beads_id
        }
        if not candidates and len(sibling_repos) == 1:
            return next(iter(sibling_repos))

        return None

    def _backfill_task_repo(self, task: BeadsTask) -> BeadsTask:
        """Fill in a repo only when task context yields a unique answer."""
        if task.repo:
            return task
        inferred = self._infer_repo_from_dependency_context(task)
        if inferred:
            task.repo = inferred
        elif self.default_repo:
            task.repo = self.default_repo
        return task

    @staticmethod
    def _infer_repo_from_title(title: str) -> Optional[str]:
        """Infer repo from a conventional task title prefix."""
        lowered = (title or "").strip().lower()
        repo_map = {
            "prime radiant:": "prime-radiant-ai",
            "agent-skills:": "agent-skills",
            "affordabot:": "affordabot",
            "llm-common:": "llm-common",
        }
        for prefix, repo in repo_map.items():
            if lowered.startswith(prefix):
                return repo
        return None

    def load_epic_tasks(self, epic_id: str) -> List[BeadsTask]:
        """
        Load all subtasks of an epic from Beads

        Uses bd show to get epic details with dependents.
        """
        try:
            result = subprocess.run(
                ["bd", "show", epic_id, "--json"],
                cwd=str(self.beads_repo_path),
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode != 0:
                return []

            data = json.loads(result.stdout)
            if not data or not isinstance(data, list):
                return []

            epic = data[0]
            tasks = []

            first_open_child = True
            for dep in epic.get("dependents", []):
                if dep.get("dependency_type") == "parent-child":
                    dep_repo = self._infer_repo_from_title(dep.get("title", ""))
                    if not dep_repo:
                        dep_repo = self.default_repo
                    self.dependency_metadata_cache[dep["id"]] = {
                        "title": dep.get("title", ""),
                        "repo": dep_repo,
                        "status": dep.get("status", "open"),
                        "close_reason": dep.get("close_reason"),
                    }
                    task = BeadsTask(
                        beads_id=dep["id"],
                        title=dep.get("title", ""),
                        description=dep.get("description", ""),
                        repo=dep_repo,
                        status=dep.get("status", "open"),
                        priority=dep.get("priority", 2),
                        details_loaded=False,
                        detail_load_error="not_loaded",
                    )
                    if self._is_terminal_dependency_status(task.status):
                        self.completed.add(task.beads_id)
                        self.dependency_status_cache[task.beads_id] = task.status
                        continue
                    # Load full task details to get dependencies
                    timeout_seconds = 10
                    task = self._load_task_details(
                        task, timeout_seconds=timeout_seconds
                    )
                    first_open_child = False
                    tasks.append(task)
                    self.tasks[task.beads_id] = task

            for task in tasks:
                self._backfill_task_repo(task)

            return tasks

        except (subprocess.TimeoutExpired, json.JSONDecodeError, KeyError):
            return []

    def _load_task_details(
        self, task: BeadsTask, timeout_seconds: int = 3
    ) -> BeadsTask:
        """Load full task details including dependencies"""
        try:
            result = subprocess.run(
                ["bd", "show", task.beads_id, "--json"],
                cwd=str(self.beads_repo_path),
                capture_output=True,
                text=True,
                timeout=timeout_seconds,
            )
            if result.returncode != 0:
                task.details_loaded = False
                task.detail_load_error = f"bd_show_failed:{result.returncode}"
                return task

            data = json.loads(result.stdout)
            if not data or not isinstance(data, list):
                task.details_loaded = False
                task.detail_load_error = "invalid_payload"
                return task

            task_data = data[0]
            task.repo = task.repo or self._infer_repo_from_title(
                task_data.get("title", task.title)
            )
            task.description = task_data.get("description", task.description or "")
            task.dependencies = []
            for dep in task_data.get("dependencies", []):
                if dep.get("dependency_type") != "blocks":
                    continue
                dep_id = dep["id"]
                task.dependencies.append(dep_id)
                dep_repo = self._infer_repo_from_title(dep.get("title", ""))
                if not dep_repo:
                    dep_repo = self.default_repo
                self.dependency_metadata_cache[dep_id] = {
                    "title": dep.get("title", ""),
                    "repo": dep_repo,
                    "status": dep.get("status"),
                    "close_reason": dep.get("close_reason"),
                }
                if "status" in dep:
                    self.dependency_status_cache[dep_id] = dep["status"]
            task.status = task_data.get("status", task.status)
            task.details_loaded = True
            task.detail_load_error = None
            self._backfill_task_repo(task)

            return task

        except subprocess.TimeoutExpired:
            task.details_loaded = False
            task.detail_load_error = "timeout"
            return task
        except (json.JSONDecodeError, KeyError):
            task.details_loaded = False
            task.detail_load_error = "decode_error"
            return task

    def refresh_unhydrated_tasks(self, timeout_seconds: int = 10):
        """Retry dependency hydration for tasks whose details were not loaded yet."""
        for task in self.tasks.values():
            if task.details_loaded:
                continue
            if self._is_terminal_dependency_status(task.status):
                continue
            self._load_task_details(task, timeout_seconds=timeout_seconds)

    def close_beads_task(self, beads_id: str, reason: str = "") -> bool:
        """Close a task in Beads and update local status. Returns True on success."""
        try:
            cmd = ["bd", "close", beads_id]
            if reason:
                cmd += ["--reason", reason]
            result = subprocess.run(
                cmd,
                cwd=str(self.beads_repo_path),
                capture_output=True,
                text=True,
                timeout=10,
            )
            if result.returncode == 0:
                task = self.tasks.get(beads_id)
                if task:
                    task.status = "closed"
                self.dependency_status_cache[beads_id] = "closed"
                return True
            return False
        except (subprocess.TimeoutExpired, OSError):
            return False

    def refresh_task_status(
        self, beads_id: str, timeout_seconds: int = 5
    ) -> Optional[str]:
        """
        Re-poll Beads for the current status of a tracked task.

        Returns the updated status string, or None if the poll failed.
        If the task is now terminal in Beads but not yet in wave.completed,
        the caller is responsible for advancing local state.
        """
        task = self.tasks.get(beads_id)
        if not task:
            return None

        try:
            result = subprocess.run(
                ["bd", "show", beads_id, "--json"],
                cwd=str(self.beads_repo_path),
                capture_output=True,
                text=True,
                timeout=timeout_seconds,
            )
            if result.returncode != 0:
                return None

            data = json.loads(result.stdout)
            if not data or not isinstance(data, list):
                return None

            fresh_status = data[0].get("status", task.status)
            fresh_title = data[0].get("title", task.title)
            close_reason = data[0].get("close_reason")
            if close_reason:
                inferred_repo = (
                    task.repo
                    or self._infer_repo_from_title(fresh_title)
                    or self.default_repo
                )
                self.dependency_metadata_cache[beads_id] = {
                    "title": fresh_title,
                    "repo": inferred_repo or "",
                    "status": fresh_status,
                    "close_reason": close_reason,
                }

            task.status = fresh_status

            if self._is_terminal_dependency_status(fresh_status):
                self.completed.add(beads_id)
                self.dependency_status_cache[beads_id] = fresh_status

            return fresh_status
        except (subprocess.TimeoutExpired, json.JSONDecodeError, KeyError):
            return None

    def refresh_epic_truth(
        self, epic_id: str, timeout_seconds: int = 5
    ) -> Optional[str]:
        """
        Re-poll Beads for parent epic truth and child statuses.

        Returns the epic status, or None when refresh fails.
        """
        try:
            result = subprocess.run(
                ["bd", "show", epic_id, "--json"],
                cwd=str(self.beads_repo_path),
                capture_output=True,
                text=True,
                timeout=timeout_seconds,
            )
            if result.returncode != 0:
                bd_bin = os.environ.get("BD_BIN")
                if (
                    bd_bin
                    and bd_bin != "bd"
                    and "embedded Dolt requires CGO" in (result.stderr or "")
                ):
                    result = subprocess.run(
                        [bd_bin, "show", epic_id, "--json"],
                        cwd=str(self.beads_repo_path),
                        capture_output=True,
                        text=True,
                        timeout=timeout_seconds,
                    )
                if result.returncode != 0:
                    return None

            data = json.loads(result.stdout)
            if not data or not isinstance(data, list):
                return None

            epic = data[0]
            epic_status = epic.get("status")

            for dep in epic.get("dependents", []):
                if dep.get("dependency_type") != "parent-child":
                    continue
                dep_id = dep.get("id")
                if not dep_id:
                    continue

                dep_title = dep.get("title", "")
                dep_status = dep.get("status")
                dep_close_reason = dep.get("close_reason")

                task = self.tasks.get(dep_id)
                dep_repo = (
                    (task.repo if task else None)
                    or self._infer_repo_from_title(dep_title)
                    or self.dependency_metadata_cache.get(dep_id, {}).get("repo")
                    or self.default_repo
                )

                self.dependency_metadata_cache[dep_id] = {
                    "title": dep_title,
                    "repo": dep_repo or "",
                    "status": dep_status,
                    "close_reason": dep_close_reason,
                }

                if dep_status:
                    self.dependency_status_cache[dep_id] = dep_status

                if task:
                    if dep_title:
                        task.title = dep_title
                    if dep_status:
                        task.status = dep_status
                        if self._is_terminal_dependency_status(dep_status):
                            self.completed.add(dep_id)

            # If Beads marks the epic terminal, stale cached children must not
            # remain dispatchable in local wave state.
            if self._is_terminal_dependency_status(epic_status):
                for task_id, task in self.tasks.items():
                    if not self._is_terminal_dependency_status(task.status):
                        task.status = "closed"
                    self.completed.add(task_id)
                    self.dependency_status_cache[task_id] = task.status

            return epic_status
        except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError):
            return None

    def compute_layers(self, task_ids: Optional[List[str]] = None) -> List[List[str]]:
        """
        Compute execution layers using Kahn's algorithm (topological sort)

        REUSED from Ralph beads-parallel.sh lines 138-268

        Returns layers of tasks that can be executed in parallel.
        """
        tasks_to_process = task_ids or list(self.tasks.keys())
        if not tasks_to_process:
            return []

        # Compute incoming edge counts (dependencies within this set)
        incoming = {tid: 0 for tid in tasks_to_process}
        for tid in tasks_to_process:
            task = self.tasks.get(tid)
            if not task:
                continue
            for dep_id in task.dependencies:
                if dep_id in tasks_to_process:
                    incoming[tid] += 1

        # Build layers
        layers = []
        processed = set()

        while len(processed) < len(tasks_to_process):
            # Find tasks with no incoming edges that haven't been processed
            layer = [
                tid
                for tid in tasks_to_process
                if incoming[tid] == 0 and tid not in processed
            ]

            if not layer:
                # Cycle detected
                break

            layers.append(layer)
            processed.update(layer)

            # Reduce incoming count for dependents
            for tid in layer:
                task = self.tasks.get(tid)
                if not task:
                    continue
                for dep_tid in tasks_to_process:
                    dep_task = self.tasks.get(dep_tid)
                    if not dep_task:
                        continue
                    if tid in dep_task.dependencies:
                        incoming[dep_tid] -= 1

        self.layers = layers
        return layers

    def get_ready_tasks(self, layer: int = 0) -> List[str]:
        """
        Get tasks ready for execution in a specific layer

        A task is ready if all its dependencies are completed.
        """
        if layer >= len(self.layers):
            return []

        ready = []
        for tid in self.layers[layer]:
            task = self.tasks.get(tid)
            if not task:
                continue
            if not task.details_loaded:
                continue

            # Check if all dependencies are completed
            if all(
                self._is_dependency_satisfied(dep_id) for dep_id in task.dependencies
            ):
                ready.append(tid)

        return ready

    def mark_completed(self, beads_id: str):
        """Mark a task as completed"""
        self.completed.add(beads_id)

    def get_next_wave(self) -> Optional[List[str]]:
        """
        Get next wave of tasks ready for execution

        Finds first layer with ready tasks.
        """
        for layer_idx in range(len(self.layers)):
            ready = self.get_ready_tasks(layer_idx)
            if ready:
                return ready
        return None

    def describe_wave_readiness(self, timeout_seconds: int = 10) -> WaveReadiness:
        """
        Describe why the next wave is or is not dispatchable.

        Distinguishes:
        - ready tasks that can dispatch now
        - tasks waiting on unmet dependencies
        - completed/no-pending conditions
        """
        readiness = WaveReadiness()
        self.refresh_unhydrated_tasks(timeout_seconds=timeout_seconds)

        for task_id, task in self.tasks.items():
            if task_id in self.completed:
                continue

            readiness.pending_tasks.append(task_id)

            if not task.details_loaded:
                readiness.waiting_on_dependencies.append(
                    {
                        "beads_id": task_id,
                        "title": task.title,
                        "unmet_dependencies": ["task_metadata_unavailable"],
                        "dependency_statuses": {
                            "task_metadata_unavailable": task.detail_load_error
                            or "unknown"
                        },
                    }
                )
                continue

            unmet = [
                dep_id
                for dep_id in task.dependencies
                if not self._is_dependency_satisfied(dep_id)
            ]
            if unmet:
                dependency_statuses = {
                    dep_id: (
                        self.tasks[dep_id].status
                        if dep_id in self.tasks
                        else self.dependency_status_cache.get(
                            dep_id, "external_or_incomplete"
                        )
                    )
                    for dep_id in unmet
                }
                readiness.waiting_on_dependencies.append(
                    {
                        "beads_id": task_id,
                        "title": task.title,
                        "unmet_dependencies": unmet,
                        "dependency_statuses": dependency_statuses,
                    }
                )
            else:
                readiness.ready.append(task_id)

        return readiness

    def has_pending_tasks(self) -> bool:
        """Check if there are pending tasks remaining"""
        return len(self.completed) < len(self.tasks)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "default_repo": self.default_repo,
            "tasks": {tid: task.to_dict() for tid, task in self.tasks.items()},
            "layers": self.layers,
            "completed": list(self.completed),
            "dependency_status_cache": dict(self.dependency_status_cache),
            "dependency_metadata_cache": dict(self.dependency_metadata_cache),
        }

    @classmethod
    def from_dict(
        cls,
        data: Dict[str, Any],
        beads_repo_path: Optional[Path] = None,
        default_repo: Optional[str] = None,
    ) -> "BeadsWaveManager":
        """
        Restore BeadsWaveManager from serialized state

        FIX for P1: Symmetric save/load for unattended restart/resume.
        """
        manager = cls(
            beads_repo_path=beads_repo_path,
            default_repo=default_repo or data.get("default_repo"),
        )

        # Restore tasks
        if "tasks" in data:
            for tid, task_data in data["tasks"].items():
                task = BeadsTask(
                    beads_id=task_data.get("beads_id", tid),
                    title=task_data.get("title", ""),
                    description=task_data.get("description", ""),
                    repo=task_data.get("repo"),
                    status=task_data.get("status", "open"),
                    dependencies=task_data.get("dependencies", []),
                    dependents=task_data.get("dependents", []),
                    priority=task_data.get("priority", 2),
                    details_loaded=task_data.get("details_loaded", True),
                    detail_load_error=task_data.get("detail_load_error"),
                )
                manager.tasks[tid] = task

        # Restore layers
        if "layers" in data:
            manager.layers = data["layers"]

        # Restore completed set
        if "completed" in data:
            manager.completed = set(data["completed"])

        if "dependency_status_cache" in data:
            manager.dependency_status_cache = dict(data["dependency_status_cache"])

        if "dependency_metadata_cache" in data:
            manager.dependency_metadata_cache = dict(data["dependency_metadata_cache"])

        return manager
