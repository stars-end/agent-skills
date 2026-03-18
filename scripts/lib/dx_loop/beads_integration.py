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
from pathlib import Path


@dataclass
class BeadsTask:
    """Represents a Beads task with dependency metadata"""
    beads_id: str
    title: str
    repo: Optional[str] = None
    status: str = "open"
    dependencies: List[str] = field(default_factory=list)
    dependents: List[str] = field(default_factory=list)
    priority: int = 2
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "beads_id": self.beads_id,
            "title": self.title,
            "repo": self.repo,
            "status": self.status,
            "dependencies": self.dependencies,
            "dependents": self.dependents,
            "priority": self.priority,
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
    
    def __init__(self, beads_repo_path: Optional[Path] = None):
        self.beads_repo_path = beads_repo_path or Path.home() / "bd"
        self.tasks: Dict[str, BeadsTask] = {}
        self.layers: List[List[str]] = []
        self.completed: Set[str] = set()
        self.dependency_status_cache: Dict[str, str] = {}

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

        return self._is_terminal_dependency_status(self.dependency_status_cache.get(dep_id))

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
            
            for dep in epic.get("dependents", []):
                if dep.get("dependency_type") == "parent-child":
                    task = BeadsTask(
                        beads_id=dep["id"],
                        title=dep.get("title", ""),
                        repo=self._infer_repo_from_title(dep.get("title", "")),
                        status=dep.get("status", "open"),
                        priority=dep.get("priority", 2),
                    )
                    # Load full task details to get dependencies
                    task = self._load_task_details(task)
                    tasks.append(task)
                    self.tasks[task.beads_id] = task
            
            return tasks
        
        except (subprocess.TimeoutExpired, json.JSONDecodeError, KeyError):
            return []
    
    def _load_task_details(self, task: BeadsTask) -> BeadsTask:
        """Load full task details including dependencies"""
        try:
            result = subprocess.run(
                ["bd", "show", task.beads_id, "--json"],
                cwd=str(self.beads_repo_path),
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode != 0:
                return task
            
            data = json.loads(result.stdout)
            if not data or not isinstance(data, list):
                return task
            
            task_data = data[0]
            task.repo = task.repo or self._infer_repo_from_title(task_data.get("title", task.title))
            task.dependencies = []
            for dep in task_data.get("dependencies", []):
                if dep.get("dependency_type") != "blocks":
                    continue
                dep_id = dep["id"]
                task.dependencies.append(dep_id)
                if "status" in dep:
                    self.dependency_status_cache[dep_id] = dep["status"]
            task.status = task_data.get("status", task.status)
            
            return task
        
        except (subprocess.TimeoutExpired, json.JSONDecodeError, KeyError):
            return task
    
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
                tid for tid in tasks_to_process
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
            
            # Check if all dependencies are completed
            if all(self._is_dependency_satisfied(dep_id) for dep_id in task.dependencies):
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

    def describe_wave_readiness(self) -> WaveReadiness:
        """
        Describe why the next wave is or is not dispatchable.

        Distinguishes:
        - ready tasks that can dispatch now
        - tasks waiting on unmet dependencies
        - completed/no-pending conditions
        """
        readiness = WaveReadiness()

        for task_id, task in self.tasks.items():
            if task_id in self.completed:
                continue

            readiness.pending_tasks.append(task_id)

            unmet = [
                dep_id for dep_id in task.dependencies if not self._is_dependency_satisfied(dep_id)
            ]
            if unmet:
                dependency_statuses = {
                    dep_id: (
                        self.tasks[dep_id].status
                        if dep_id in self.tasks
                        else self.dependency_status_cache.get(dep_id, "external_or_incomplete")
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
            "tasks": {tid: task.to_dict() for tid, task in self.tasks.items()},
            "layers": self.layers,
            "completed": list(self.completed),
            "dependency_status_cache": dict(self.dependency_status_cache),
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any], beads_repo_path: Optional[Path] = None) -> "BeadsWaveManager":
        """
        Restore BeadsWaveManager from serialized state
        
        FIX for P1: Symmetric save/load for unattended restart/resume.
        """
        manager = cls(beads_repo_path=beads_repo_path)
        
        # Restore tasks
        if "tasks" in data:
            for tid, task_data in data["tasks"].items():
                task = BeadsTask(
                    beads_id=task_data.get("beads_id", tid),
                    title=task_data.get("title", ""),
                    repo=task_data.get("repo"),
                    status=task_data.get("status", "open"),
                    dependencies=task_data.get("dependencies", []),
                    dependents=task_data.get("dependents", []),
                    priority=task_data.get("priority", 2),
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
        
        return manager
