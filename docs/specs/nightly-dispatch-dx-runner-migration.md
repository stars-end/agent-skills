# Migration Spec: nightly-dispatch → dx-runner

**Status:** DRAFT - Awaiting Review
**Author:** Claude (Infra Analysis)
**Date:** 2026-02-19
**Target Merge:** TBD

---

## Executive Summary

Migrate `nightly_dispatch.py` from the deprecated `dx-dispatch.py` interface to the canonical `dx-runner` unified dispatch system. This addresses the ongoing cron failures caused by:
1. Outdated dispatch interface lacking model availability checks
2. Silent claim failures (`bd update --claim` returns exit 0 on failure)
3. SSH hostname resolution issues in legacy dispatch path

---

## Beads Structure

```
bd-XXXX (Epic)
├── nightly-dispatch: migrate to dx-runner
│
├── bd-XXXX.1 (Feature)
│   ├── Update dispatch interface to dx-runner
│   │
│   ├── bd-XXXX.1.1 (Task) - Replace dx-dispatch.py calls with dx-runner
│   ├── bd-XXXX.1.2 (Task) - Update prompt delivery mechanism
│   └── bd-XXXX.1.3 (Task) - Update timeout and monitoring logic
│
├── bd-XXXX.2 (Feature)
│   ├── Add preflight + fallback provider logic
│   │
│   ├── bd-XXXX.2.1 (Task) - Implement dx-runner preflight check
│   ├── bd-XXXX.2.2 (Task) - Implement provider fallback chain
│   └── bd-XXXX.2.3 (Task) - Add canonical model availability check
│
├── bd-XXXX.3 (Feature)
│   ├── Fix claim detection and error handling
│   │
│   ├── bd-XXXX.3.1 (Task) - Detect claim failure via stderr parsing
│   ├── bd-XXXX.3.2 (Task) - Capture dx-runner stdout for error messages
│   └── bd-XXXX.3.3 (Task) - Add structured logging with failure codes
│
├── bd-XXXX.4 (Feature)
│   ├── Configuration and deployment updates
│   │
│   ├── bd-XXXX.4.1 (Task) - Remove hardcoded DEFAULT_VM
│   ├── bd-XXXX.4.2 (Task) - Update crontab command path
│   └── bd-XXXX.4.3 (Task) - Add integration test
│
└── bd-XXXX.5 (Feature) [OPTIONAL]
    ├── bd CLI claim exit code fix
    │
    └── bd-XXXX.5.1 (Task) - Fix bd update --claim to return non-zero on failure
```

---

## Dependency Graph

```
bd-XXXX.1.1 ─────────────────────────────────────────┐
      │                                               │
      ▼                                               │
bd-XXXX.1.2 ─────────────────────────────────────────┤
      │                                               │
      ▼                                               │
bd-XXXX.1.3 ─────────────────────────────────────────┤
      │                                               │
      ├───────────────────────────────────────────────┤
      │                                               │
      ▼                                               ▼
bd-XXXX.2.1 ◄───────────────────────────────── bd-XXXX.3.1
      │                                               │
      ▼                                               │
bd-XXXX.2.2                                          │
      │                                               │
      ▼                                               │
bd-XXXX.2.3                                          │
      │                                               │
      ├───────────────────────────────────────────────┤
      │                                               │
      ▼                                               ▼
bd-XXXX.3.2 ◄─────────────────────────────────────────┘
      │
      ▼
bd-XXXX.3.3
      │
      ▼
bd-XXXX.4.1
      │
      ▼
bd-XXXX.4.2
      │
      ▼
bd-XXXX.4.3 (integration test - BLOCKING for merge)

bd-XXXX.5.1 (optional, external dependency on bd CLI)
```

---

## Feature Specifications

---

### Feature: bd-XXXX.1 — Update dispatch interface to dx-runner

**Goal:** Replace deprecated dx-dispatch.py with canonical dx-runner interface.

**Files Changed:**
- `prime-radiant-ai/scripts/jules/nightly_dispatch.py`

---

#### Task: bd-XXXX.1.1 — Replace dx-dispatch.py calls with dx-runner

**Description:** Replace the subprocess call to `dx-dispatch.py` with `dx-runner start`.

**Current Code (lines 187-199):**
```python
def dispatch_to_opencode(issue: Dict, dry_run: bool = False) -> bool:
    """Dispatch via dx-dispatch with worktree isolation."""
    beads_id = issue["id"]
    prompt = build_fix_prompt(issue)

    # Determine path to dx-dispatch.py
    import os
    dispatch_script = os.environ.get("DX_DISPATCH_PATH")
    if not dispatch_script:
        dispatch_script = str(Path.home() / "agent-skills" / "scripts" / "dx-dispatch.py")

    cmd = [
        sys.executable, dispatch_script,
        DEFAULT_VM, prompt,
        "--beads", beads_id,
        "--repo", REPO,
        "--attach",  # Use opencode run --attach for reliable execution
    ]
```

**New Code:**
```python
def dispatch_to_dxrunner(
    issue: Dict,
    provider: str = "opencode",
    dry_run: bool = False
) -> bool:
    """Dispatch via dx-runner with provider selection.

    Args:
        issue: Beads issue dict with 'id', 'title', 'description'
        provider: Provider name ('opencode', 'cc-glm', 'gemini')
        dry_run: If True, simulate dispatch without executing

    Returns:
        True if dispatch initiated successfully, False otherwise
    """
    beads_id = issue["id"]
    prompt = build_fix_prompt(issue)

    # Write prompt to temp file (dx-runner requires --prompt-file)
    prompt_file = Path(f"/tmp/nightly-dispatch-{beads_id}.prompt")
    prompt_file.write_text(prompt)

    cmd = [
        str(Path.home() / "agent-skills" / "scripts" / "dx-runner"),
        "start",
        "--beads", beads_id,
        "--provider", provider,
        "--prompt-file", str(prompt_file),
        "--repo", REPO,
    ]

    return cmd
```

**Acceptance Criteria:**
- [ ] dx-dispatch.py no longer called
- [ ] Prompt written to temp file before dispatch
- [ ] Command uses `dx-runner start` with correct flags
- [ ] Function returns command list for subprocess execution

**Dependencies:** None (entry point)

---

#### Task: bd-XXXX.1.2 — Update prompt delivery mechanism

**Description:** dx-runner requires `--prompt-file` instead of positional argument. Implement temp file handling.

**Implementation:**
```python
def _write_prompt_file(beads_id: str, prompt: str) -> Path:
    """Write prompt to temp file for dx-runner consumption.

    Uses /tmp prefix for automatic cleanup and avoids worktree paths.
    """
    prompt_file = Path(f"/tmp/nightly-dispatch-{beads_id}.prompt")
    prompt_file.write_text(prompt)
    return prompt_file

def _cleanup_prompt_file(prompt_file: Path) -> None:
    """Remove prompt file after dispatch (best-effort)."""
    try:
        prompt_file.unlink(missing_ok=True)
    except Exception:
        pass  # Non-critical cleanup
```

**Acceptance Criteria:**
- [ ] Prompt files written to /tmp with beads_id in filename
- [ ] Cleanup called after dispatch completion
- [ ] No prompt file leakage on error paths

**Dependencies:** bd-XXXX.1.1

---

#### Task: bd-XXXX.1.3 — Update timeout and monitoring logic

**Description:** dx-runner handles timeouts internally. Update the dispatch function to use dx-runner's built-in monitoring instead of subprocess timeout.

**Current Code (lines 217-233):**
```python
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=DISPATCH_TIMEOUT)

        if result.returncode == 0:
            logger.info(f"✅ Dispatched {beads_id} successfully")
            return True
        else:
            logger.error(f"❌ Failed to dispatch {beads_id}: {result.stderr[:200]}")
            return False
    except subprocess.TimeoutExpired:
        logger.error(f"⏰ Dispatch {beads_id} timed out after {DISPATCH_TIMEOUT}s")
        run_cmd(["bd", "update", beads_id, "--unclaim"], check=False)
        return False
```

**New Code:**
```python
    # dx-runner handles timeout internally; we just need to capture result
    # Fire-and-forget dispatch - monitoring happens via dx-runner status
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30  # Short timeout - just for dx-runner start ack
        )

        if result.returncode == 0:
            logger.info(f"✅ Dispatched {beads_id} to {provider}")
            return True
        else:
            # Parse dx-runner error output
            error_msg = _parse_dxrunner_error(result.stdout, result.stderr)
            logger.error(f"❌ Failed to dispatch {beads_id}: {error_msg}")
            return False
    except subprocess.TimeoutExpired:
        # dx-runner start itself timed out (unexpected)
        logger.error(f"⏰ dx-runner start timed out for {beads_id}")
        run_cmd(["bd", "update", beads_id, "--unclaim"], check=False)
        return False
    finally:
        _cleanup_prompt_file(prompt_file)
```

**Key Change:** Timeout reduced from 1200s (20min) to 30s because dx-runner dispatches asynchronously. The actual job timeout is managed by dx-runner internally.

**Acceptance Criteria:**
- [ ] Dispatch timeout reduced to 30s (ack timeout only)
- [ ] Cleanup happens in finally block
- [ ] Error parsing handles dx-runner output format

**Dependencies:** bd-XXXX.1.2

---

### Feature: bd-XXXX.2 — Add preflight + fallback provider logic

**Goal:** Check provider availability before dispatch and fall back gracefully when canonical model is unavailable.

**Files Changed:**
- `prime-radiant-ai/scripts/jules/nightly_dispatch.py`

---

#### Task: bd-XXXX.2.1 — Implement dx-runner preflight check

**Description:** Run `dx-runner preflight --provider <name>` before dispatch to verify availability.

**Implementation:**
```python
def check_provider_available(provider: str) -> Tuple[bool, str]:
    """Check if a provider is available via dx-runner preflight.

    Returns:
        Tuple of (is_available, error_message)
    """
    cmd = [
        str(Path.home() / "agent-skills" / "scripts" / "dx-runner"),
        "preflight",
        "--provider", provider,
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if result.returncode == 0:
            return (True, "")

        # Parse preflight failure reason
        error_msg = _parse_preflight_error(result.stdout)
        return (False, error_msg)

    except subprocess.TimeoutExpired:
        return (False, "Preflight check timed out")
    except Exception as e:
        return (False, str(e))


def _parse_preflight_error(output: str) -> str:
    """Extract error message from preflight output."""
    for line in output.split('\n'):
        if 'ERROR:' in line:
            return line.split('ERROR:')[-1].strip()
        if 'canonical model' in line.lower() and 'missing' in line.lower():
            return "Canonical model unavailable"
    return output[:200]
```

**Acceptance Criteria:**
- [ ] Preflight check runs before any dispatch
- [ ] Returns structured availability status
- [ ] Parses error messages for logging

**Dependencies:** bd-XXXX.1.3

---

#### Task: bd-XXXX.2.2 — Implement provider fallback chain

**Description:** Define fallback order when primary provider unavailable.

**Implementation:**
```python
# Configuration constants
PROVIDER_FALLBACK_CHAIN = ["opencode", "cc-glm", "gemini"]
PRIMARY_PROVIDER = "opencode"

def select_provider() -> Tuple[str, str]:
    """Select best available provider.

    Returns:
        Tuple of (provider_name, selection_reason)
    """
    for provider in PROVIDER_FALLBACK_CHAIN:
        available, error = check_provider_available(provider)
        if available:
            if provider == PRIMARY_PROVIDER:
                return (provider, "primary")
            else:
                return (provider, f"fallback ({PRIMARY_PROVIDER} unavailable: {error})")

    # No providers available
    return (None, "No providers available")


def main():
    # ... existing code ...

    # Select provider before dispatch
    provider, reason = select_provider()
    if provider is None:
        logger.error(f"❌ {reason}")
        sys.exit(1)

    if reason != "primary":
        logger.warning(f"⚠️ Using fallback provider: {provider} ({reason})")

    # Update dispatch calls to use selected provider
    dispatched = dispatch_parallel(work_queue, max_dispatch, args.dry_run, provider=provider)
```

**Acceptance Criteria:**
- [ ] Tries opencode first, falls back to cc-glm, then gemini
- [ ] Logs reason for fallback selection
- [ ] Exits with error if no providers available

**Dependencies:** bd-XXXX.2.1

---

#### Task: bd-XXXX.2.3 — Add canonical model availability check

**Description:** Log detailed model availability status during preflight.

**Implementation:**
```python
def log_provider_status(provider: str) -> None:
    """Log detailed provider status for debugging."""
    cmd = [
        str(Path.home() / "agent-skills" / "scripts" / "dx-runner"),
        "preflight",
        "--provider", provider,
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

    # Log key status lines
    for line in result.stdout.split('\n'):
        if any(keyword in line.lower() for keyword in ['ok', 'error', 'missing', 'model']):
            logger.info(f"[preflight/{provider}] {line.strip()}")
```

**Acceptance Criteria:**
- [ ] Model availability logged at INFO level
- [ ] Clear indication when canonical model is missing

**Dependencies:** bd-XXXX.2.2

---

### Feature: bd-XXXX.3 — Fix claim detection and error handling

**Goal:** Properly detect claim failures and capture error messages from dx-runner.

**Files Changed:**
- `prime-radiant-ai/scripts/jules/nightly_dispatch.py`

---

#### Task: bd-XXXX.3.1 — Detect claim failure via stderr parsing

**Description:** Since `bd update --claim` returns exit 0 on failure, parse stderr for error indication.

**Current Code (lines 206-211):**
```python
    # Claim issue to prevent duplicate dispatch
    try:
        run_cmd(["bd", "update", beads_id, "--claim"])
    except Exception:
        logger.info(f"Skipping {beads_id}: already claimed or not claimable")
        return False
```

**New Code:**
```python
def claim_issue(beads_id: str) -> Tuple[bool, str]:
    """Attempt to claim a Beads issue.

    Returns:
        Tuple of (success, error_message)
    """
    result = subprocess.run(
        ["bd", "update", beads_id, "--claim"],
        capture_output=True,
        text=True
    )

    # Check stderr for claim failure (bd CLI returns exit 0 even on failure)
    stderr = result.stderr.strip()
    stdout = result.stdout.strip()

    if "already claimed" in stderr.lower() or "already claimed" in stdout.lower():
        return (False, f"already claimed: {_extract_claim_owner(stderr or stdout)}")

    if "error" in stderr.lower():
        return (False, stderr[:200])

    # Exit code 0 and no error messages = success
    if result.returncode == 0:
        return (True, "")

    return (False, f"Unknown error (exit {result.returncode})")


def _extract_claim_owner(output: str) -> str:
    """Extract claim owner from bd output."""
    # Pattern: "already claimed by Recovery Agent"
    import re
    match = re.search(r'already claimed by ([^\s]+)', output, re.IGNORECASE)
    if match:
        return match.group(1)
    return "unknown"
```

**Acceptance Criteria:**
- [ ] Parses stderr/stdout for "already claimed" message
- [ ] Extracts and logs claim owner
- [ ] Returns structured success/failure status

**Dependencies:** None (can be done in parallel with bd-XXXX.1.*)

---

#### Task: bd-XXXX.3.2 — Capture dx-runner stdout for error messages

**Description:** dx-runner outputs errors to stdout. Ensure we capture and log both streams.

**Implementation:**
```python
def _parse_dxrunner_error(stdout: str, stderr: str) -> str:
    """Parse error message from dx-runner output.

    dx-runner logs errors to stdout with [ERROR] prefix.
    """
    # Check stdout first (dx-runner primary output)
    for line in stdout.split('\n'):
        if '[ERROR]' in line:
            return line.split('[ERROR]')[-1].strip()

    # Fall back to stderr
    if stderr.strip():
        return stderr[:200]

    # No error message found
    return "Unknown error (no error output)"
```

**Acceptance Criteria:**
- [ ] Parses stdout for [ERROR] lines
- [ ] Falls back to stderr if no stdout errors
- [ ] Returns meaningful error string

**Dependencies:** bd-XXXX.3.1

---

#### Task: bd-XXXX.3.3 — Add structured logging with failure codes

**Description:** Add failure taxonomy for monitoring and alerting.

**Implementation:**
```python
from enum import Enum
from dataclasses import dataclass

class DispatchFailureCode(Enum):
    """Failure codes for dispatch operations."""
    CLAIM_FAILED = "claim_failed"
    PREFLIGHT_FAILED = "preflight_failed"
    PROVIDER_UNAVAILABLE = "provider_unavailable"
    RUNNER_ERROR = "runner_error"
    TIMEOUT = "timeout"
    UNKNOWN = "unknown"


@dataclass
class DispatchResult:
    """Result of a dispatch attempt."""
    success: bool
    beads_id: str
    provider: str
    failure_code: DispatchFailureCode = None
    error_message: str = ""
    duration_ms: int = 0


def log_dispatch_result(result: DispatchResult) -> None:
    """Log dispatch result with structured fields."""
    if result.success:
        logger.info(f"✅ DISPATCH_SUCCESS beads={result.beads_id} provider={result.provider}")
    else:
        logger.error(
            f"❌ DISPATCH_FAILURE beads={result.beads_id} "
            f"provider={result.provider} code={result.failure_code.value} "
            f"error={result.error_message}"
        )
```

**Acceptance Criteria:**
- [ ] All dispatch outcomes logged with structured format
- [ ] Failure codes enable filtering/alerting
- [ ] Duration tracked for performance monitoring

**Dependencies:** bd-XXXX.3.2

---

### Feature: bd-XXXX.4 — Configuration and deployment updates

**Goal:** Update configuration to be provider-agnostic and deploy changes.

**Files Changed:**
- `prime-radiant-ai/scripts/jules/nightly_dispatch.py`
- `agent-skills/scripts/dx-nightly-dispatcher.sh` (wrapper script)
- Crontab entry

---

#### Task: bd-XXXX.4.1 — Remove hardcoded DEFAULT_VM

**Description:** Replace hardcoded VM with provider-agnostic configuration.

**Current Code (lines 43-46):**
```python
# VM Configuration
DEFAULT_VM = "epyc6"
REPO = "prime-radiant-ai"
SLACK_CHANNEL = "C09MQGMFKDE"
```

**New Code:**
```python
# Configuration
PRIMARY_PROVIDER = "opencode"
REPO = "prime-radiant-ai"
SLACK_CHANNEL = "C09MQGMFKDE"

# Fallback order when primary unavailable
PROVIDER_FALLBACK_CHAIN = ["opencode", "cc-glm", "gemini"]
```

**Acceptance Criteria:**
- [ ] No hardcoded VM references
- [ ] Provider selection via configuration
- [ ] Fallback chain configurable

**Dependencies:** bd-XXXX.3.3

---

#### Task: bd-XXXX.4.2 — Update crontab command path

**Description:** Update the crontab entry to use the new dispatch script.

**Current Crontab:**
```
0 6-13 * * * /opt/homebrew/bin/bash /Users/fengning/agent-skills/scripts/dx-job-wrapper.sh nightly-dispatch -- /Users/fengning/agent-skills/scripts/dx-nightly-dispatcher.sh >> /Users/fengning/logs/dx/nightly-dispatch.log 2>&1
```

**Changes:**
- No crontab change required (wrapper script stays the same)
- Update `dx-nightly-dispatcher.sh` to ensure environment is correct

**File: `agent-skills/scripts/dx-nightly-dispatcher.sh`:**
```bash
#!/usr/bin/env bash
# dx-nightly-dispatcher.sh - Nightly Fleet Dispatcher wrapper
# Updated for dx-runner interface

set -euo pipefail

REPO_ROOT="/Users/fengning/prime-radiant-ai"
AGENTSKILLS_DIR="/Users/fengning/agent-skills"

# Setup environment
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin"
export BEADS_DIR="$HOME/bd/.beads"

cd "$REPO_ROOT"

# Ensure mise is loaded
if command -v mise &> /dev/null; then
    eval "$(mise activate bash)"
fi

# Run the dispatcher
exec "$REPO_ROOT/backend/.venv/bin/python" scripts/jules/nightly_dispatch.py "$@"
```

**Acceptance Criteria:**
- [ ] Wrapper script updated with correct paths
- [ ] No crontab modification required

**Dependencies:** bd-XXXX.4.1

---

#### Task: bd-XXXX.4.3 — Add integration test

**Description:** Add test that verifies the dispatch flow works end-to-end.

**File: `prime-radiant-ai/scripts/jules/test_nightly_dispatch.py`**

**Implementation:**
```python
#!/usr/bin/env python3
"""Integration tests for nightly_dispatch.py"""

import pytest
from unittest.mock import patch, MagicMock
from pathlib import Path

# Import from nightly_dispatch
import sys
sys.path.insert(0, str(Path(__file__).parent))
from nightly_dispatch import (
    claim_issue,
    check_provider_available,
    select_provider,
    _parse_dxrunner_error,
    _write_prompt_file,
)


class TestClaimIssue:
    def test_claim_success(self):
        """Claim returns success when bd succeeds."""
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,
                stdout="",
                stderr=""
            )
            success, error = claim_issue("bd-test")
            assert success is True
            assert error == ""

    def test_claim_already_claimed(self):
        """Claim detects 'already claimed' in output."""
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = MagicMock(
                returncode=0,  # Note: bd returns 0 even on failure!
                stdout="",
                stderr="Error claiming bd-test: already claimed by Recovery Agent"
            )
            success, error = claim_issue("bd-test")
            assert success is False
            assert "already claimed" in error.lower()


class TestProviderSelection:
    def test_primary_provider_available(self):
        """Selects primary provider when available."""
        with patch('nightly_dispatch.check_provider_available') as mock_check:
            mock_check.side_effect = lambda p: (p == "opencode", "")
            provider, reason = select_provider()
            assert provider == "opencode"
            assert reason == "primary"

    def test_fallback_to_cc_glm(self):
        """Falls back to cc-glm when opencode unavailable."""
        with patch('nightly_dispatch.check_provider_available') as mock_check:
            mock_check.side_effect = lambda p: (
                p != "opencode",
                "canonical model missing" if p == "opencode" else ""
            )
            provider, reason = select_provider()
            assert provider == "cc-glm"
            assert "fallback" in reason.lower()


class TestPromptFile:
    def test_write_and_cleanup(self, tmp_path):
        """Prompt file is written and cleaned up."""
        with patch('nightly_dispatch.Path') as mock_path:
            mock_path.return_value = tmp_path / "test.prompt"
            prompt_file = _write_prompt_file("bd-test", "test prompt")
            assert prompt_file.exists()
            assert prompt_file.read_text() == "test prompt"


class TestErrorParsing:
    def test_parse_dxrunner_stdout_error(self):
        """Parses [ERROR] from stdout."""
        stdout = "[06:00:00] [ERROR] Dispatch failed: model unavailable"
        stderr = ""
        error = _parse_dxrunner_error(stdout, stderr)
        assert "model unavailable" in error


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
```

**Acceptance Criteria:**
- [ ] Tests cover claim detection, provider selection, prompt handling
- [ ] Tests pass before merge
- [ ] Added to CI if applicable

**Dependencies:** bd-XXXX.4.2

**BLOCKS MERGE:** This task must pass before the feature can be merged.

---

### Feature: bd-XXXX.5 (OPTIONAL) — bd CLI claim exit code fix

**Goal:** Fix `bd update --claim` to return non-zero exit code when claim fails.

**Files Changed:**
- Beads CLI (external repository)

---

#### Task: bd-XXXX.5.1 — Fix bd update --claim to return non-zero on failure

**Description:** The bd CLI should return exit code 1 when `--claim` fails due to "already claimed".

**Current Behavior:**
```bash
$ bd update bd-xxx --claim
Error claiming bd-xxx: already claimed by Recovery Agent
$ echo $?
0
```

**Expected Behavior:**
```bash
$ bd update bd-xxx --claim
Error claiming bd-xxx: already claimed by Recovery Agent
$ echo $?
1
```

**Implementation Note:** This requires changes to the bd CLI codebase. The workaround in bd-XXXX.3.1 (stderr parsing) handles this in the meantime.

**Acceptance Criteria:**
- [ ] `bd update --claim` returns exit 1 when already claimed
- [ ] Returns exit 1 on any claim error
- [ ] Returns exit 0 only on successful claim

**Dependencies:** None (external to this migration)

**Status:** OPTIONAL - Can be deferred; workaround in place.

---

## Migration Rollout Plan

### Phase 1: Development (Day 1-2)
1. Create Beads epic and features
2. Implement bd-XXXX.1, bd-XXXX.2, bd-XXXX.3 in worktree
3. Write integration tests (bd-XXXX.4.3)
4. Local validation with `--dry-run`

### Phase 2: Staging Validation (Day 3)
1. Deploy to staging/test cron
2. Run with `--dry-run` on schedule
3. Monitor logs for provider selection, error handling
4. Verify fallback chain works

### Phase 3: Production Rollout (Day 4)
1. Merge PR to master
2. Update wrapper script on production VM
3. Monitor first few cron runs
4. Verify #dx-alerts shows recovery

### Rollback Plan
If issues detected:
1. Revert to previous nightly_dispatch.py version
2. Restore old wrapper script
3. Cron continues with old interface

---

## Success Criteria

| Metric | Before | After |
|--------|--------|-------|
| Cron success rate | ~0% (all failing) | >95% |
| Error message visibility | Empty ("Failed: ") | Structured with codes |
| Provider fallback | None | opencode → cc-glm → gemini |
| Claim detection | Silent failure | Logged with owner |

---

## Open Questions for Review

1. **Provider priority:** Is the fallback order `opencode → cc-glm → gemini` correct? Should gemini be prioritized over cc-glm?

2. **Timeout tuning:** 30s for dispatch ack timeout - is this sufficient? dx-runner start should be fast.

3. **Parallel dispatch:** Should we reduce MAX_PARALLEL from 2 to 1 during migration for safety?

4. **Monitoring:** Should we add Slack alerts for fallback provider usage?

5. **bd-XXXX.5 priority:** Should the bd CLI fix be a blocker or can it be deferred?

---

## Appendix: File Changes Summary

| File | Changes |
|------|---------|
| `prime-radiant-ai/scripts/jules/nightly_dispatch.py` | Major refactor - dispatch interface, preflight, error handling |
| `prime-radiant-ai/scripts/jules/test_nightly_dispatch.py` | NEW - Integration tests |
| `agent-skills/scripts/dx-nightly-dispatcher.sh` | Minor - ensure paths correct |

---

*End of Spec - Awaiting Review*
