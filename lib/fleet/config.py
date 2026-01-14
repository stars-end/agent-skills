"""
Fleet configuration management.

Loads ~/.agent-skills/fleet-config.json with tier-aware defaults.
"""

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class BackendConfig:
    """Configuration for a single backend (OpenCode VM or Jules)."""
    type: str  # "opencode" or "jules"
    name: str  # e.g., "epyc6", "jules-cloud"
    priority: int = 99
    url: str | None = None  # For OpenCode
    ssh: str | None = None  # For OpenCode SSH target
    max_concurrent: int = 2
    three_gate_required: bool = False  # For Jules


@dataclass
class MonitoringConfig:
    """Monitoring thresholds configuration."""
    poll_interval_seconds: int = 60
    
    # Mode-specific thresholds
    smoke_stale_minutes: int = 5
    smoke_timeout_minutes: int = 10
    
    real_stale_minutes: int = 15
    real_timeout_minutes: int = 30
    
    nightly_stale_minutes: int = 20
    nightly_timeout_minutes: int = 60
    
    def get_thresholds(self, mode: str) -> tuple[int, int]:
        """Get (stale_threshold, timeout) for a given mode."""
        if mode == "smoke":
            return (self.smoke_stale_minutes, self.smoke_timeout_minutes)
        elif mode == "nightly":
            return (self.nightly_stale_minutes, self.nightly_timeout_minutes)
        else:  # real is default
            return (self.real_stale_minutes, self.real_timeout_minutes)


@dataclass
class SlackConfig:
    """Slack integration configuration."""
    audit_channel: str = ""
    post_on_dispatch: bool = True
    post_activity_updates: bool = True
    post_on_complete: bool = True


@dataclass 
class FleetConfig:
    """Main configuration class for FleetDispatcher."""
    
    strategy: str = "priority"
    monitoring: MonitoringConfig = field(default_factory=MonitoringConfig)
    slack: SlackConfig = field(default_factory=SlackConfig)
    backends: list[BackendConfig] = field(default_factory=list)
    
    _config_path: Path = field(default_factory=lambda: Path.home() / ".agent-skills" / "fleet-config.json")
    
    def __post_init__(self):
        """Load config from file if it exists."""
        self._load_from_file()
    
    def _load_from_file(self) -> None:
        """Load configuration from JSON file."""
        if not self._config_path.exists():
            # Use defaults + load vm-endpoints.json for backwards compatibility
            self._load_legacy_endpoints()
            return
        
        try:
            with open(self._config_path) as f:
                data = json.load(f)
            
            self.strategy = data.get("strategy", self.strategy)
            
            # Load monitoring config
            mon = data.get("monitoring", {})
            smoke = mon.get("_smoke", {})
            real = mon.get("_real", {})
            nightly = mon.get("_nightly", {})
            
            self.monitoring = MonitoringConfig(
                poll_interval_seconds=mon.get("poll_interval_seconds", 60),
                smoke_stale_minutes=smoke.get("stale_threshold_minutes", 5),
                smoke_timeout_minutes=smoke.get("timeout_minutes", 10),
                real_stale_minutes=real.get("stale_threshold_minutes", 15),
                real_timeout_minutes=real.get("timeout_minutes", 30),
                nightly_stale_minutes=nightly.get("stale_threshold_minutes", 20),
                nightly_timeout_minutes=nightly.get("timeout_minutes", 60),
            )
            
            # Load slack config
            slack = data.get("slack", {})
            self.slack = SlackConfig(
                audit_channel=slack.get("audit_channel", ""),
                post_on_dispatch=slack.get("post_on_dispatch", True),
                post_activity_updates=slack.get("post_activity_updates", True),
                post_on_complete=slack.get("post_on_complete", True),
            )
            
            # Load backends
            self.backends = []
            for b in data.get("backends", []):
                self.backends.append(BackendConfig(
                    type=b.get("type", "opencode"),
                    name=b.get("name", "unknown"),
                    priority=b.get("priority", 99),
                    url=b.get("url"),
                    ssh=b.get("ssh"),
                    max_concurrent=b.get("max_concurrent", 2),
                    three_gate_required=b.get("three_gate_required", False),
                ))
            
        except (json.JSONDecodeError, KeyError) as e:
            print(f"Warning: Failed to load fleet-config.json: {e}")
            self._load_legacy_endpoints()
    
    def _load_legacy_endpoints(self) -> None:
        """Load from legacy vm-endpoints.json for backwards compatibility."""
        legacy_path = Path.home() / ".agent-skills" / "vm-endpoints.json"
        if not legacy_path.exists():
            return
        
        try:
            with open(legacy_path) as f:
                data = json.load(f)
            
            # Handle nested 'vms' structure
            vms = data.get("vms", data)  # Fallback to root if no 'vms' key
            
            priority = 1
            for vm_name, config in vms.items():
                if isinstance(config, dict) and "opencode" in config:
                    self.backends.append(BackendConfig(
                        type="opencode",
                        name=vm_name,
                        priority=priority,
                        url=config.get("opencode"),
                        ssh=config.get("ssh"),
                        max_concurrent=2,
                    ))
                    priority += 1
            
            # Always add Jules as fallback
            self.backends.append(BackendConfig(
                type="jules",
                name="jules-cloud",
                priority=99,
                three_gate_required=True,
                max_concurrent=10,
            ))
            
        except (json.JSONDecodeError, KeyError) as e:
            print(f"Warning: Failed to load vm-endpoints.json: {e}")
    
    def get_backend(self, name: str) -> BackendConfig | None:
        """Get backend by name."""
        for backend in self.backends:
            if backend.name == name:
                return backend
        return None
    
    def get_opencode_backends(self) -> list[BackendConfig]:
        """Get all OpenCode backends sorted by priority."""
        return sorted(
            [b for b in self.backends if b.type == "opencode"],
            key=lambda b: b.priority
        )
    
    def get_jules_backend(self) -> BackendConfig | None:
        """Get Jules backend if configured."""
        for backend in self.backends:
            if backend.type == "jules":
                return backend
        return None
