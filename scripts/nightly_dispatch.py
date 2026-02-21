#!/usr/bin/env python3
"""
nightly_dispatch.py - Autonomous fleet dispatcher for nightly bug fixes

Runs hourly (6am-1pm UTC = 10pm-5am PT) to automatically fix P0/P1 bugs
without human intervention using the dx-runner interface.

Usage:
    python nightly_dispatch.py [--dry-run]

Environment:
    DX_RUNNER_PATH: Path to dx-runner binary (default: /usr/local/bin/dx-runner)
    SLACK_WEBHOOK: Slack webhook URL for alerts
    GITHUB_TOKEN: GitHub token for PR creation
"""

import argparse
import json
import logging
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# Setup logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("nightly_dispatch")


@dataclass
class PreflightResult:
    """Stores preflight check result for a single provider."""

    provider: str
    available: bool
    error: Optional[str] = None
    model_checked: Optional[str] = None


@dataclass
class NightlyDispatchConfig:
    """Configuration for nightly dispatch with migration-safe defaults."""

    # Provider fallback chain
    PROVIDER_CHAIN: List[str] = field(
        default_factory=lambda: ["opencode", "cc-glm", "gemini"]
    )

    # Strict model gating per provider
    PROVIDER_MODELS: Dict[str, List[str]] = field(
        default_factory=lambda: {
            "opencode": ["zhipuai-coding-plan/glm-5"],  # STRICT - single model ID
            "cc-glm": ["cc-glm"],
            "gemini": ["gemini-2.5-pro", "gemini-2.0-flash"],
        }
    )

    # Timeout: ack only (dx-runner handles job timeout internally)
    DISPATCH_ACK_TIMEOUT_SEC: int = 45  # 45s with one retry
    DISPATCH_ACK_RETRIES: int = 1

    # Migration safety: reduce parallelism for 48h
    MAX_PARALLEL: int = 1  # Temporarily reduced from 2
    MAX_PARALLEL_POST_MIGRATION: int = 2  # Restore after 48h clean runs

    # Alerting
    ALERT_ON_PROVIDER_FALLBACK: bool = True
    ALERT_ON_NO_PROVIDERS: bool = True
    ALERT_RATE_LIMIT_MINUTES: int = 30  # Don't spam Slack

    # Overload protection
    MAX_CRITICAL_BUGS: int = 10
    MAX_DISPATCHES_PER_RUN: int = 3

    # Dispatch timeout
    DISPATCH_TIMEOUT_MINUTES: int = 20

    _migration_start_file: Path = field(
        default_factory=lambda: Path.home()
        / ".agent-skills"
        / ".nightly-dispatch-migration-start"
    )

    def __post_init__(self):
        """Initialize migration start time if not set."""
        if not self._migration_start_file.exists():
            self._migration_start_file.parent.mkdir(parents=True, exist_ok=True)
            self._migration_start_file.write_text(
                datetime.now(timezone.utc).isoformat()
            )

    def should_restore_parallelism(self) -> bool:
        """Check if 48h have passed since migration to restore MAX_PARALLEL."""
        if not self._migration_start_file.exists():
            return False
        try:
            migration_start = datetime.fromisoformat(
                self._migration_start_file.read_text().strip()
            )
            elapsed = datetime.now(timezone.utc) - migration_start
            return elapsed >= timedelta(hours=48)
        except (ValueError, IOError):
            return False

    def get_max_parallel(self) -> int:
        """Get current MAX_PARALLEL based on migration timeline."""
        if self.should_restore_parallelism():
            return self.MAX_PARALLEL_POST_MIGRATION
        return self.MAX_PARALLEL


class SlackAlerter:
    """Handles Slack alerts with rate limiting."""

    def __init__(self, webhook_url: Optional[str] = None):
        self.webhook_url = webhook_url or os.environ.get("SLACK_WEBHOOK")
        self._last_alert_time: Dict[str, datetime] = {}
        self._rate_limit_minutes = 30

    def _should_send_alert(self, alert_type: str) -> bool:
        """Check if enough time has passed since last alert of this type."""
        now = datetime.now(timezone.utc)
        last_time = self._last_alert_time.get(alert_type)

        if last_time is None:
            return True

        elapsed = now - last_time
        return elapsed >= timedelta(minutes=self._rate_limit_minutes)

    def _send_alert(self, message: str, alert_type: str = "general") -> bool:
        """Send alert to Slack with rate limiting."""
        if not self.webhook_url:
            logger.warning("No Slack webhook configured, skipping alert")
            return False

        if not self._should_send_alert(alert_type):
            logger.info(f"Rate limiting {alert_type} alert, skipping")
            return False

        try:
            import urllib.request
            import urllib.parse

            payload = json.dumps({"text": message}).encode("utf-8")
            req = urllib.request.Request(
                self.webhook_url,
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )

            with urllib.request.urlopen(req, timeout=10) as response:
                if response.status == 200:
                    self._last_alert_time[alert_type] = datetime.now(timezone.utc)
                    return True
                else:
                    logger.error(f"Slack alert failed with status {response.status}")
                    return False
        except Exception as e:
            logger.error(f"Failed to send Slack alert: {e}")
            return False

    def alert_fallback(self, from_provider: str, to_provider: str, reason: str) -> bool:
        """Alert when falling back to secondary provider."""
        message = (
            f"⚠️ Provider Fallback: {from_provider} → {to_provider}\n"
            f"Reason: {reason}\n"
            f"Time: {datetime.now(timezone.utc).isoformat()}"
        )
        return self._send_alert(message, f"fallback_{from_provider}_{to_provider}")

    def alert_no_providers(self, failures: List[Tuple[str, Optional[str]]]) -> bool:
        """Alert when no providers are available."""
        failure_str = "\n".join(
            [f"  - {p}: {e or 'unknown error'}" for p, e in failures]
        )
        message = (
            f"🚨 CRITICAL: No providers available!\n"
            f"Failures:\n{failure_str}\n"
            f"Time: {datetime.now(timezone.utc).isoformat()}"
        )
        return self._send_alert(message, "no_providers")

    def alert_overload(self, bug_count: int) -> bool:
        """Alert when bug count exceeds threshold."""
        message = (
            f"⚠️ Overload Protection Triggered\n"
            f"Bug count: {bug_count} (threshold: 10)\n"
            f"Reducing dispatch rate to 1/hour\n"
            f"Time: {datetime.now(timezone.utc).isoformat()}"
        )
        return self._send_alert(message, "overload")

    def alert_dispatch_complete(
        self, beads_id: str, provider: str, success: bool
    ) -> bool:
        """Alert when dispatch completes."""
        status = "✅ Success" if success else "❌ Failed"
        message = (
            f"{status}: Nightly dispatch complete\n"
            f"Beads ID: {beads_id}\n"
            f"Provider: {provider}\n"
            f"Time: {datetime.now(timezone.utc).isoformat()}"
        )
        return self._send_alert(message, f"dispatch_complete_{beads_id}")


class NightlyDispatcher:
    """Main dispatcher for nightly bug fixes using dx-runner."""

    def __init__(self, config: Optional[NightlyDispatchConfig] = None):
        self.config = config or NightlyDispatchConfig()
        self.alerter = SlackAlerter()
        self.dx_runner_path = Path(
            os.environ.get("DX_RUNNER_PATH", "/usr/local/bin/dx-runner")
        )
        self.github_token = os.environ.get("GITHUB_TOKEN")

    def run_preflight(self, provider: str, model: str) -> PreflightResult:
        """Run preflight check for a provider with strict model gating."""
        logger.info(f"Running preflight for {provider} with model {model}")

        try:
            # Include --model flag to enforce strict model gating
            result = subprocess.run(
                [
                    str(self.dx_runner_path),
                    "preflight",
                    "--provider", provider,
                    "--model", model,
                ],
                capture_output=True,
                text=True,
                timeout=30,
            )

            # exit 0 = available, exit 1 = unavailable (both valid)
            if result.returncode == 0:
                return PreflightResult(
                    provider=provider, available=True, model_checked=model
                )
            else:
                error_msg = result.stderr.strip() or f"Provider {provider} unavailable"
                return PreflightResult(
                    provider=provider,
                    available=False,
                    error=error_msg,
                    model_checked=model,
                )
        except subprocess.TimeoutExpired:
            return PreflightResult(
                provider=provider,
                available=False,
                error="Preflight timeout",
                model_checked=model,
            )
        except Exception as e:
            return PreflightResult(
                provider=provider, available=False, error=str(e), model_checked=model
            )

    def select_provider(self) -> Tuple[str, Optional[str], Dict[str, PreflightResult]]:
        """
        Select provider with full preflight history for proper error attribution.

        Returns:
            (selected_provider, selected_model, preflight_results_by_provider)
        """
        # Use dict for safe lookups instead of list indices
        preflight_results: Dict[str, PreflightResult] = {}

        # === PRIMARY: OpenCode with strict model gate ===
        opencode_model = "zhipuai-coding-plan/glm-5"
        opencode_result = self.run_preflight("opencode", opencode_model)
        preflight_results["opencode"] = opencode_result

        if opencode_result.available:
            logger.info(f"Selected provider: opencode with model {opencode_model}")
            return "opencode", opencode_model, preflight_results

        # === FALLBACK 1: cc-glm ===
        logger.warning(f"OpenCode unavailable: {opencode_result.error}")
        cc_glm_result = self.run_preflight("cc-glm", "cc-glm")
        preflight_results["cc-glm"] = cc_glm_result

        if cc_glm_result.available:
            # Report the PRIMARY (OpenCode) failure reason using dict lookup
            primary_failure = preflight_results["opencode"].error
            logger.warning(
                f"Provider fallback: OpenCode unavailable, using cc-glm. "
                f"Primary failure: {primary_failure}"
            )
            if self.config.ALERT_ON_PROVIDER_FALLBACK:
                self.alerter.alert_fallback(
                    "opencode", "cc-glm", primary_failure or "unknown"
                )
            return "cc-glm", "cc-glm", preflight_results

        # === FALLBACK 2: gemini (terminal) ===
        logger.warning(f"cc-glm unavailable: {cc_glm_result.error}")
        gemini_result = self.run_preflight("gemini", "gemini-2.5-pro")
        preflight_results["gemini"] = gemini_result

        if gemini_result.available:
            # Report the actual cc-glm failure using dict lookup
            cc_glm_failure = preflight_results["cc-glm"].error
            logger.error(
                f"Provider fallback: cc-glm unavailable, using gemini (terminal). "
                f"cc-glm failure: {cc_glm_failure}"
            )
            if self.config.ALERT_ON_PROVIDER_FALLBACK:
                self.alerter.alert_fallback(
                    "cc-glm", "gemini", cc_glm_failure or "unknown"
                )
            return "gemini", "gemini-2.5-pro", preflight_results

        # === NO PROVIDERS AVAILABLE ===
        logger.error("No providers available!")
        if self.config.ALERT_ON_NO_PROVIDERS:
            failures = [
                (k, v.error) for k, v in preflight_results.items() if not v.available
            ]
            self.alerter.alert_no_providers(failures)

        raise RuntimeError(
            f"No providers available. All failures: "
            f"{[(k, v.error) for k, v in preflight_results.items() if not v.available]}"
        )

    def parse_claim_error(self, stderr: str) -> Optional[Dict[str, str]]:
        """
        Parse 'already claimed' error from bd CLI stderr.

        FIXED: Capture multi-word owner names to end-of-line or timestamp.
        """
        # First, try to match with timestamp (owner is everything between "by" and " at ")
        pattern_with_ts = (
            r"already claimed by\s+(.+?)\s+at\s+(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})"
        )
        match = re.search(pattern_with_ts, stderr, re.IGNORECASE)
        if match:
            return {
                "claimed_by": match.group(1).strip(),
                "claimed_at": match.group(2),
            }

        # If no timestamp, capture to end of line
        pattern_no_ts = r"already claimed by\s+(.+?)$"
        match = re.search(pattern_no_ts, stderr, re.IGNORECASE | re.MULTILINE)
        if match:
            return {
                "claimed_by": match.group(1).strip(),
                "claimed_at": None,
            }

        return None

    def write_prompt_secure(self, beads_id: str, prompt: str) -> Path:
        """
        Write prompt to secure temporary file with restrictive permissions.
        """
        # Sanitize beads_id for safe filename usage
        safe_id = re.sub(r"[^a-zA-Z0-9_-]", "_", beads_id)[:50]

        fd, path_str = tempfile.mkstemp(
            prefix=f"ndisp_{safe_id}_", suffix=".prompt", dir="/tmp"
        )
        try:
            with os.fdopen(fd, "w") as f:
                f.write(prompt)
            # Restrict to owner read/write only (0o600)
            os.chmod(path_str, 0o600)
            return Path(path_str)
        except Exception:
            # Cleanup on failure
            try:
                os.unlink(path_str)
            except OSError:
                pass
            raise

    def cleanup_prompt_file(self, path: Path) -> None:
        """Securely remove prompt file with error handling."""
        try:
            path.unlink(missing_ok=True)
        except Exception as e:
            logger.warning(f"Failed to cleanup prompt file {path}: {e}")

    def claim_issue(self, beads_id: str) -> bool:
        """Claim a beads issue, handling already-claimed errors."""
        logger.info(f"Claiming issue {beads_id}")

        try:
            result = subprocess.run(
                ["bd", "update", beads_id, "--status=in-progress"],
                capture_output=True,
                text=True,
                timeout=10,
            )

            # bd CLI may return exit 0 even when already claimed, check stderr
            if result.returncode == 0:
                # Check stderr for "already claimed" message
                if result.stderr and "already claimed" in result.stderr.lower():
                    claim_info = self.parse_claim_error(result.stderr)
                    if claim_info:
                        logger.info(
                            f"Issue {beads_id} already claimed by {claim_info['claimed_by']}"
                        )
                    return False
                return True
            else:
                # Check if it's an "already claimed" error
                claim_info = self.parse_claim_error(result.stderr)
                if claim_info:
                    logger.info(
                        f"Issue {beads_id} already claimed by {claim_info['claimed_by']}"
                    )
                    return False
                logger.error(f"Failed to claim {beads_id}: {result.stderr}")
                return False

        except Exception as e:
            logger.error(f"Error claiming {beads_id}: {e}")
            return False

    def dispatch_with_runner(
        self, beads_id: str, provider: str, model: str, prompt_file: Path
    ) -> bool:
        """Dispatch a job using dx-runner with strict model gating."""
        logger.info(f"Dispatching {beads_id} via {provider} with model {model}")

        try:
            # Include --model flag to enforce strict model gating
            result = subprocess.run(
                [
                    str(self.dx_runner_path),
                    "start",
                    "--beads", beads_id,
                    "--provider", provider,
                    "--model", model,
                    "--prompt-file", str(prompt_file),
                ],
                capture_output=True,
                text=True,
                timeout=self.config.DISPATCH_ACK_TIMEOUT_SEC,
            )

            if result.returncode == 0:
                logger.info(f"Successfully dispatched {beads_id}")
                return True
            else:
                logger.error(f"Dispatch failed: {result.stderr}")
                return False

        except subprocess.TimeoutExpired:
            logger.error(f"Dispatch timeout for {beads_id}")
            return False
        except Exception as e:
            logger.error(f"Dispatch error for {beads_id}: {e}")
            return False

    def check_dispatch_status(self, beads_id: str) -> str:
        """Check status of a dispatched job."""
        try:
            result = subprocess.run(
                [str(self.dx_runner_path), "check", "--beads", beads_id],
                capture_output=True,
                text=True,
                timeout=10,
            )

            if result.returncode == 0:
                return "running"
            else:
                return "stopped"
        except Exception:
            return "unknown"

    def stop_dispatch(self, beads_id: str) -> None:
        """Stop a dispatched job."""
        try:
            subprocess.run(
                [str(self.dx_runner_path), "stop", "--beads", beads_id],
                capture_output=True,
                timeout=10,
            )
        except Exception as e:
            logger.warning(f"Error stopping {beads_id}: {e}")

    def get_open_bugs(self) -> List[Dict[str, Any]]:
        """Query Beads for open P0/P1 bugs."""
        logger.info("Querying for open P0/P1 bugs")

        try:
            result = subprocess.run(
                ["bd", "list", "--status=open", "--type=bug", "--json"],
                capture_output=True,
                text=True,
                timeout=30,
            )

            if result.returncode != 0:
                logger.error(f"Failed to query bugs: {result.stderr}")
                return []

            # Parse JSON output
            bugs = json.loads(result.stdout) if result.stdout else []

            # Filter for P0/P1 priority (Beads uses numeric: 0=P0, 1=P1, 2=P2, etc.)
            critical_bugs = [b for b in bugs if b.get("priority") in [0, 1]]

            logger.info(f"Found {len(critical_bugs)} P0/P1 bugs")
            return critical_bugs

        except Exception as e:
            logger.error(f"Error querying bugs: {e}")
            return []

    def deduplicate_bugs(self, bugs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Deduplicate bugs by error signature."""
        seen_signatures = set()
        unique_bugs = []

        for bug in bugs:
            # Create signature from title + first 100 chars of description
            sig = f"{bug.get('title', '')}:{str(bug.get('description', ''))[:100]}"
            if sig not in seen_signatures:
                seen_signatures.add(sig)
                unique_bugs.append(bug)

        logger.info(f"Deduplicated {len(bugs)} bugs to {len(unique_bugs)} unique")
        return unique_bugs

    def build_fix_prompt(self, bug: Dict[str, Any]) -> str:
        """Build prompt for fixing a bug."""
        return f"""Fix the following bug:

Title: {bug.get("title", "Unknown")}
ID: {bug.get("id", "Unknown")}
Priority: {bug.get("priority", "Unknown")}

Description:
{bug.get("description", "No description provided")}

Steps:
1. Reproduce the bug
2. Identify root cause
3. Implement fix
4. Run make ci-lite
5. Create PR with proper metadata
6. Post to Slack when done
"""

    def run(self, dry_run: bool = False) -> None:
        """Main dispatch loop."""
        logger.info(f"🌙 Starting Nightly Dispatch (dry_run={dry_run})")

        # 1. Pre-dispatch health check
        logger.info("Step 1: Pre-dispatch health check")
        try:
            provider, model, _ = self.select_provider()
            logger.info(f"Health check passed: {provider} available")
        except RuntimeError as e:
            logger.error(f"Health check failed: {e}")
            return

        # 2. Query beads for bugs
        logger.info("Step 2: Querying Beads")
        bugs = self.get_open_bugs()
        bugs = self.deduplicate_bugs(bugs)

        # 3. Mode selection
        if not bugs:
            logger.info("No P0/P1 bugs found - entering IMPROVE mode (not implemented)")
            return

        logger.info(f"REPAIR mode: {len(bugs)} bugs to fix")

        # 4. Overload protection
        if len(bugs) > self.config.MAX_CRITICAL_BUGS:
            logger.warning(
                f"Overload: {len(bugs)} bugs > {self.config.MAX_CRITICAL_BUGS} threshold"
            )
            self.alerter.alert_overload(len(bugs))
            # Reduce to 1/hour
            bugs = bugs[:1]
            logger.info("Reduced to 1 bug due to overload protection")

        # 5. Dispatch (parallel, max 2 at a time)
        max_parallel = self.config.get_max_parallel()
        dispatches_to_run = bugs[: self.config.MAX_DISPATCHES_PER_RUN]

        logger.info(
            f"Dispatching {len(dispatches_to_run)} bugs (max_parallel={max_parallel})"
        )

        if dry_run:
            logger.info("[DRY-RUN] Would dispatch:")
            for bug in dispatches_to_run:
                logger.info(f"  - {bug.get('id')}: {bug.get('title')}")
            return

        # Process dispatches concurrently with max_parallel limit
        def process_bug(bug: Dict[str, Any]) -> None:
            """Process a single bug dispatch."""
            beads_id = bug.get("id")
            if not beads_id:
                logger.warning(f"Bug missing ID, skipping: {bug}")
                return

            logger.info(f"Processing {beads_id}")

            # Claim issue
            if not self.claim_issue(beads_id):
                logger.info(f"Skipping {beads_id} - already claimed")
                return

            # Build prompt
            prompt = self.build_fix_prompt(bug)

            # Write secure prompt file
            prompt_file = None
            try:
                prompt_file = self.write_prompt_secure(beads_id, prompt)

                # Select provider (may have changed since health check)
                provider, model, _ = self.select_provider()

                # Dispatch with model enforcement
                success = self.dispatch_with_runner(
                    beads_id, provider, model, prompt_file
                )

                if success:
                    self.alerter.alert_dispatch_complete(beads_id, provider, True)
                else:
                    self.alerter.alert_dispatch_complete(beads_id, provider, False)

            except Exception as e:
                logger.error(f"Error dispatching {beads_id}: {e}")
                self.alerter.alert_dispatch_complete(beads_id, "unknown", False)
            finally:
                if prompt_file:
                    self.cleanup_prompt_file(prompt_file)

        # Use ThreadPoolExecutor for concurrent processing with max_parallel limit
        with ThreadPoolExecutor(max_workers=max_parallel) as executor:
            futures = {
                executor.submit(process_bug, bug): bug for bug in dispatches_to_run
            }
            for future in as_completed(futures):
                bug = futures[future]
                try:
                    future.result()
                except Exception as e:
                    logger.error(f"Bug {bug.get('id')} generated an exception: {e}")

        logger.info("🌙 Nightly Dispatch complete")


def main():
    parser = argparse.ArgumentParser(description="Run nightly bug fix dispatch")
    parser.add_argument(
        "--dry-run", action="store_true", help="Don't actually dispatch"
    )
    parser.add_argument("--config", type=str, help="Path to config file (JSON)")
    args = parser.parse_args()

    # Load config if provided
    config = None
    if args.config:
        try:
            with open(args.config) as f:
                config_data = json.load(f)
                config = NightlyDispatchConfig(**config_data)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            sys.exit(1)

    dispatcher = NightlyDispatcher(config)
    dispatcher.run(dry_run=args.dry_run)


if __name__ == "__main__":
    main()
