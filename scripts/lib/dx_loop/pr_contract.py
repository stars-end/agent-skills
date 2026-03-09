"""
dx-loop PR artifact contract enforcement

Treats runs without PR_URL/PR_HEAD_SHA as incomplete.
Enforces PR artifact requirement for merge_ready state.
"""

from __future__ import annotations
from dataclasses import dataclass
from typing import Optional, Dict, Any
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


class PRContractEnforcer:
    """
    Enforces PR artifact requirement for dx-loop completion
    
    Key difference from Ralph: Missing PR artifacts means incomplete,
    not success. This ensures every implementation produces a PR artifact.
    """
    
    def __init__(self):
        self.artifacts: Dict[str, PRArtifact] = {}  # beads_id -> PRArtifact
    
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
