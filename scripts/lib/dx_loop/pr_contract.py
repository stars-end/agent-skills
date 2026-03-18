"""
dx-loop PR artifact contract enforcement

Treats runs without PR_URL/PR_HEAD_SHA as incomplete.
Enforces PR artifact requirement for merge_ready state.
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional, Dict, Any, List
import re


@dataclass
class PRArtifact:
    """PR artifact required for completion"""
    pr_url: str
    pr_head_sha: str
    
    def is_valid(self) -> bool:
        """Validate PR artifacts are present and well-formed"""
        if not self.pr_url or not self.pr_head_sha:
            return False
        
        # Validate URL format
        if not self._is_valid_pr_url(self.pr_url):
            return False
        
        # Validate SHA format (40 hex characters)
        if not re.match(r'^[a-f0-9]{40}$', self.pr_head_sha):
            return False
        
        return True
    
    def _is_valid_pr_url(self, url: str) -> bool:
        """Check if URL looks like a GitHub PR URL"""
        # Accept GitHub PR URLs
        patterns = [
            r'^https://github\.com/[^/]+/[^/]+/pull/\d+$',
            r'^https://github\.com/[^/]+/[^/]+/pull/\d+/',
        ]
        return any(re.match(p, url) for p in patterns)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "pr_url": self.pr_url,
            "pr_head_sha": self.pr_head_sha,
            "is_valid": self.is_valid(),
        }


@dataclass
class ImplementationReturn:
    """Structured implementer return compatible with tech-lead-handoff."""

    mode: str
    pr_url: Optional[str] = None
    pr_head_sha: Optional[str] = None
    beads_epic: Optional[str] = None
    beads_subtask: Optional[str] = None
    beads_dependencies: Optional[str] = None
    validation: List[str] = field(default_factory=list)
    changed_files: List[str] = field(default_factory=list)
    risks: List[str] = field(default_factory=list)
    decisions: List[str] = field(default_factory=list)
    how_to_review: List[str] = field(default_factory=list)
    raw_text: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "mode": self.mode,
            "pr_url": self.pr_url,
            "pr_head_sha": self.pr_head_sha,
            "beads_epic": self.beads_epic,
            "beads_subtask": self.beads_subtask,
            "beads_dependencies": self.beads_dependencies,
            "validation": list(self.validation),
            "changed_files": list(self.changed_files),
            "risks": list(self.risks),
            "decisions": list(self.decisions),
            "how_to_review": list(self.how_to_review),
            "raw_text": self.raw_text,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "ImplementationReturn":
        return cls(
            mode=data.get("mode", ""),
            pr_url=data.get("pr_url"),
            pr_head_sha=data.get("pr_head_sha"),
            beads_epic=data.get("beads_epic"),
            beads_subtask=data.get("beads_subtask"),
            beads_dependencies=data.get("beads_dependencies"),
            validation=list(data.get("validation", [])),
            changed_files=list(data.get("changed_files", [])),
            risks=list(data.get("risks", [])),
            decisions=list(data.get("decisions", [])),
            how_to_review=list(data.get("how_to_review", [])),
            raw_text=data.get("raw_text", ""),
        )


class PRContractEnforcer:
    """
    Enforces PR artifact requirement for dx-loop completion
    
    Key difference from Ralph: Missing PR artifacts means incomplete,
    not success. This ensures every implementation produces a PR artifact.
    """
    
    def __init__(self):
        self.artifacts: Dict[str, PRArtifact] = {}  # beads_id -> PRArtifact
        self.implementation_returns: Dict[str, ImplementationReturn] = {}
    
    def register_artifact(self, beads_id: str, pr_url: str, pr_head_sha: str) -> PRArtifact:
        """Register PR artifact for a Beads item"""
        artifact = PRArtifact(pr_url=pr_url, pr_head_sha=pr_head_sha)
        self.artifacts[beads_id] = artifact
        return artifact
    
    def get_artifact(self, beads_id: str) -> Optional[PRArtifact]:
        """Get PR artifact for a Beads item"""
        return self.artifacts.get(beads_id)
    
    def has_valid_artifact(self, beads_id: str) -> bool:
        """Check if Beads item has valid PR artifact"""
        artifact = self.artifacts.get(beads_id)
        return artifact is not None and artifact.is_valid()
    
    def extract_from_agent_output(self, output: str) -> Optional[PRArtifact]:
        """
        Extract PR artifacts from agent output
        
        Looks for patterns like:
        - PR_URL: https://github.com/...
        - PR_HEAD_SHA: abc123...
        """
        pr_url = None
        pr_head_sha = None
        
        for line in output.split('\n'):
            line = line.strip()
            if line.startswith('PR_URL:'):
                pr_url = line.split(':', 1)[1].strip()
            elif line.startswith('PR_HEAD_SHA:'):
                pr_head_sha = line.split(':', 1)[1].strip()
        
        if pr_url and pr_head_sha:
            return PRArtifact(pr_url=pr_url, pr_head_sha=pr_head_sha)
        
        return None

    def register_implementation_return(
        self, beads_id: str, implementation_return: ImplementationReturn
    ) -> ImplementationReturn:
        self.implementation_returns[beads_id] = implementation_return
        if implementation_return.pr_url and implementation_return.pr_head_sha:
            self.register_artifact(
                beads_id, implementation_return.pr_url, implementation_return.pr_head_sha
            )
        return implementation_return

    def get_implementation_return(
        self, beads_id: str
    ) -> Optional[ImplementationReturn]:
        return self.implementation_returns.get(beads_id)

    def extract_implementation_return(self, output: str) -> Optional[ImplementationReturn]:
        """
        Extract a tech-lead-handoff compatible implementation return from agent text.
        """
        if not output:
            return None

        marker_patterns = [
            r"## Tech Lead Review \(Implementation Return\)",
            r"MODE:\s*implementation_return",
        ]
        start_index: Optional[int] = None
        for pattern in marker_patterns:
            matches = list(re.finditer(pattern, output, flags=re.IGNORECASE))
            if matches:
                start_index = matches[-1].start()
                break

        if start_index is None:
            return None

        handoff_text = output[start_index:].strip()
        lines = [line.rstrip() for line in handoff_text.splitlines()]
        if not lines:
            return None

        implementation_return = ImplementationReturn(
            mode="implementation_return",
            raw_text=handoff_text,
        )
        current_section: Optional[str] = None

        section_map = {
            "validation": "validation",
            "changed files summary": "changed_files",
            "risks / blockers": "risks",
            "decisions needed": "decisions",
            "how to review": "how_to_review",
        }

        for raw_line in lines:
            line = raw_line.strip()
            if not line:
                continue

            if line.startswith("### "):
                current_section = section_map.get(line[4:].strip().lower())
                continue

            if line.startswith("- "):
                body = line[2:].strip()
                if ":" in body:
                    key, value = body.split(":", 1)
                    normalized = key.strip().lower()
                    value = value.strip()
                    if normalized == "mode":
                        implementation_return.mode = value
                        current_section = None
                        continue
                    if normalized == "pr_url":
                        implementation_return.pr_url = value
                        current_section = None
                        continue
                    if normalized == "pr_head_sha":
                        implementation_return.pr_head_sha = value
                        current_section = None
                        continue
                    if normalized == "beads_epic":
                        implementation_return.beads_epic = value
                        current_section = None
                        continue
                    if normalized == "beads_subtask":
                        implementation_return.beads_subtask = value
                        current_section = None
                        continue
                    if normalized == "beads_dependencies":
                        implementation_return.beads_dependencies = value
                        current_section = None
                        continue
                if current_section:
                    getattr(implementation_return, current_section).append(body)
                continue

            numbered = re.match(r"^\d+\.\s+(.*)$", line)
            if numbered and current_section:
                getattr(implementation_return, current_section).append(
                    numbered.group(1).strip()
                )
                continue

            if line.startswith("PR_URL:"):
                implementation_return.pr_url = line.split(":", 1)[1].strip()
                continue
            if line.startswith("PR_HEAD_SHA:"):
                implementation_return.pr_head_sha = line.split(":", 1)[1].strip()
                continue
            if line.startswith("MODE:"):
                implementation_return.mode = line.split(":", 1)[1].strip()

        if implementation_return.mode.lower() != "implementation_return":
            return None
        if not implementation_return.pr_url or not implementation_return.pr_head_sha:
            return None
        return implementation_return

    def to_dict(self) -> Dict[str, Any]:
        return {
            "artifacts": {
                bid: artifact.to_dict()
                for bid, artifact in self.artifacts.items()
            },
            "implementation_returns": {
                bid: implementation_return.to_dict()
                for bid, implementation_return in self.implementation_returns.items()
            },
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "PRContractEnforcer":
        enforcer = cls()
        for bid, artifact_data in data.get("artifacts", {}).items():
            enforcer.artifacts[bid] = PRArtifact(
                pr_url=artifact_data.get("pr_url", ""),
                pr_head_sha=artifact_data.get("pr_head_sha", ""),
            )
        for bid, implementation_return in data.get("implementation_returns", {}).items():
            enforcer.implementation_returns[bid] = ImplementationReturn.from_dict(
                implementation_return
            )
        return enforcer
    
    def is_merge_ready(self, beads_id: str, checks_passing: bool = True) -> bool:
        """
        Determine if Beads item is merge-ready
        
        Requires:
        1. Valid PR artifact (PR_URL + PR_HEAD_SHA)
        2. Checks passing
        """
        if not self.has_valid_artifact(beads_id):
            return False
        
        if not checks_passing:
            return False
        
        return True
