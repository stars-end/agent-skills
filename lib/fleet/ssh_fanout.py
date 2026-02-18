"""
SSH Fanout utilities for fleet dispatch.

Provides:
- Canonical host->user mapping from fleet config
- Deterministic preflight checks (host resolvable, user mapping, auth mode)
- Standardized logging (host, user, command summary, normalized outcome)
- Bounded retry semantics with clear terminal state
"""

import subprocess
import socket
import re
from dataclasses import dataclass
from enum import Enum
from typing import Callable
from datetime import datetime


class PreflightStatus(Enum):
    """Result of preflight checks."""
    OK = "ok"
    HOST_UNRESOLVABLE = "host_unresolvable"
    HOST_UNREACHABLE = "host_unreachable"
    USER_MAPPING_MISSING = "user_mapping_missing"
    AUTH_MODE_INVALID = "auth_mode_invalid"
    TIMEOUT = "timeout"


class FanoutOutcome(Enum):
    """Terminal outcome states for fanout operations."""
    SUCCESS = "success"
    FAILURE = "failure"
    ABORTED = "aborted"
    TIMEOUT = "timeout"
    PREFLIGHT_FAILED = "preflight_failed"


@dataclass
class HostMapping:
    """Canonical host configuration."""
    hostname: str
    user: str
    ssh_target: str  # Full SSH target (user@host)
    auth_mode: str  # "tailscale", "ssh_key", or "local"
    aliases: list[str]  # Alternative names


@dataclass
class PreflightResult:
    """Result of preflight validation."""
    status: PreflightStatus
    host_mapping: HostMapping | None = None
    error_detail: str | None = None
    duration_ms: int = 0


@dataclass
class FanoutResult:
    """Result of a fanout SSH operation."""
    outcome: FanoutOutcome
    host: str
    user: str
    command_summary: str
    exit_code: int | None
    stdout: str | None
    stderr: str | None
    error: str | None = None
    attempts: int = 1
    duration_ms: int = 0


# Canonical host->user mapping (source of truth)
# Derived from P6_MULTI_VM_ORCHESTRATION.md and fleet-config.json
CANONICAL_HOST_MAPPINGS: list[HostMapping] = [
    HostMapping(
        hostname="homedesktop-wsl",
        user="fengning",
        ssh_target="fengning@homedesktop-wsl",
        auth_mode="local",
        aliases=["homedesktop", "wsl", "local"],
    ),
    HostMapping(
        hostname="macmini",
        user="fengning",
        ssh_target="fengning@macmini",
        auth_mode="tailscale",
        aliases=["mac", "mac-mini"],
    ),
    HostMapping(
        hostname="epyc6",
        user="feng",
        ssh_target="feng@epyc6",
        auth_mode="tailscale",
        aliases=["epyc", "gpu"],
    ),
]


def get_host_mapping(host: str) -> HostMapping | None:
    """Get canonical host mapping by hostname or alias.

    Args:
        host: Hostname or alias (e.g., "epyc6", "macmini", "gpu")

    Returns:
        HostMapping if found, None otherwise
    """
    host_lower = host.lower().strip()

    for mapping in CANONICAL_HOST_MAPPINGS:
        if mapping.hostname.lower() == host_lower:
            return mapping
        if host_lower in [a.lower() for a in mapping.aliases]:
            return mapping

    return None


def resolve_hostname(hostname: str, timeout_sec: float = 5.0) -> tuple[bool, str]:
    """Check if hostname is DNS resolvable.

    Args:
        hostname: Hostname to resolve
        timeout_sec: DNS resolution timeout

    Returns:
        Tuple of (success, resolved_ip_or_error)
    """
    try:
        # Set socket timeout
        socket.setdefaulttimeout(timeout_sec)
        ip = socket.gethostbyname(hostname)
        return (True, ip)
    except socket.gaierror as e:
        return (False, f"DNS resolution failed: {e}")
    except socket.timeout:
        return (False, "DNS resolution timed out")
    finally:
        socket.setdefaulttimeout(None)


def check_host_reachable(
    hostname: str,
    port: int = 22,
    timeout_sec: float = 5.0
) -> tuple[bool, str]:
    """Check if host is reachable on SSH port.

    Args:
        hostname: Hostname to check
        port: SSH port (default 22)
        timeout_sec: Connection timeout

    Returns:
        Tuple of (reachable, detail_message)
    """
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout_sec)
        result = sock.connect_ex((hostname, port))
        sock.close()

        if result == 0:
            return (True, f"Port {port} open")
        else:
            return (False, f"Port {port} unreachable (error code: {result})")
    except socket.gaierror as e:
        return (False, f"DNS error: {e}")
    except socket.timeout:
        return (False, f"Connection timed out after {timeout_sec}s")
    except OSError as e:
        return (False, f"Network error: {e}")


def validate_auth_mode(mapping: HostMapping) -> tuple[bool, str]:
    """Validate that the required auth mode is available.

    Args:
        mapping: Host mapping with auth_mode

    Returns:
        Tuple of (valid, detail_message)
    """
    if mapping.auth_mode == "local":
        # Local mode always valid
        return (True, "local mode")

    if mapping.auth_mode == "tailscale":
        # Check if tailscale is available
        result = subprocess.run(
            ["which", "tailscale"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            return (True, "tailscale available")
        else:
            return (False, "tailscale not found in PATH")

    if mapping.auth_mode == "ssh_key":
        # Check if SSH agent or key is available (best-effort)
        # We don't fail here - just warn. Actual SSH will reveal auth issues.
        return (True, "ssh_key mode (will verify on connect)")

    return (False, f"Unknown auth mode: {mapping.auth_mode}")


def run_preflight_checks(
    host: str,
    check_reachable: bool = True,
    timeout_sec: float = 5.0
) -> PreflightResult:
    """Run deterministic preflight checks before fanout.

    Checks performed (in order):
    1. Host mapping exists (user mapping check)
    2. Hostname is DNS resolvable
    3. Host is reachable on SSH port (if check_reachable)
    4. Auth mode is valid

    Args:
        host: Target hostname or alias
        check_reachable: Whether to check TCP reachability
        timeout_sec: Timeout for each check

    Returns:
        PreflightResult with status and details
    """
    start = datetime.now()

    # 1. Check host mapping
    mapping = get_host_mapping(host)
    if not mapping:
        return PreflightResult(
            status=PreflightStatus.USER_MAPPING_MISSING,
            host_mapping=None,
            error_detail=f"No host mapping found for '{host}'. "
                        f"Valid hosts: {[m.hostname for m in CANONICAL_HOST_MAPPINGS]}",
            duration_ms=_elapsed_ms(start),
        )

    # 2. Check DNS resolution
    resolved, detail = resolve_hostname(mapping.hostname, timeout_sec)
    if not resolved:
        return PreflightResult(
            status=PreflightStatus.HOST_UNRESOLVABLE,
            host_mapping=mapping,
            error_detail=f"Cannot resolve {mapping.hostname}: {detail}",
            duration_ms=_elapsed_ms(start),
        )

    # 3. Check reachability (optional)
    if check_reachable:
        reachable, detail = check_host_reachable(mapping.hostname, timeout_sec=timeout_sec)
        if not reachable:
            return PreflightResult(
                status=PreflightStatus.HOST_UNREACHABLE,
                host_mapping=mapping,
                error_detail=f"{mapping.hostname} unreachable: {detail}",
                duration_ms=_elapsed_ms(start),
            )

    # 4. Validate auth mode
    auth_valid, detail = validate_auth_mode(mapping)
    if not auth_valid:
        return PreflightResult(
            status=PreflightStatus.AUTH_MODE_INVALID,
            host_mapping=mapping,
            error_detail=f"Auth mode validation failed: {detail}",
            duration_ms=_elapsed_ms(start),
        )

    return PreflightResult(
        status=PreflightStatus.OK,
        host_mapping=mapping,
        error_detail=None,
        duration_ms=_elapsed_ms(start),
    )


def _elapsed_ms(start: datetime) -> int:
    """Calculate elapsed milliseconds since start."""
    return int((datetime.now() - start).total_seconds() * 1000)


def _summarize_command(command: str, max_len: int = 60) -> str:
    """Create a brief summary of a command for logging.

    Strips sensitive patterns and truncates.
    """
    # Remove common sensitive patterns
    sanitized = re.sub(r'--token[=\s]+\S+', '--token=***', command)
    sanitized = re.sub(r'--password[=\s]+\S+', '--password=***', sanitized)
    sanitized = re.sub(r'--key[=\s]+\S+', '--key=***', sanitized)

    # Truncate
    if len(sanitized) > max_len:
        return sanitized[:max_len - 3] + "..."

    return sanitized


def _strip_ansi(text: str) -> str:
    """Remove ANSI escape codes from text."""
    ansi_pattern = r'\x1b\[[0-9;]*[mGKH]'
    return re.sub(ansi_pattern, '', text)


def fanout_ssh(
    host: str,
    command: str,
    timeout_sec: float = 60.0,
    max_retries: int = 1,
    retry_delay_sec: float = 2.0,
    preflight: bool = True,
    batch_mode: bool = True,
    log_callback: Callable[[str, str], None] | None = None,
) -> FanoutResult:
    """Execute SSH command with fanout hardening.

    This is the hardened entry point for SSH-based dispatch operations.
    It performs preflight checks, executes with batch mode to avoid hangs,
    and provides bounded retry with clear terminal states.

    Args:
        host: Target hostname or alias
        command: Command to execute on remote host
        timeout_sec: Command timeout (default 60s)
        max_retries: Maximum retry attempts (default 1, so max 2 total attempts)
        retry_delay_sec: Delay between retries
        preflight: Whether to run preflight checks (default True)
        batch_mode: Use SSH BatchMode=yes to prevent password prompts (default True)
        log_callback: Optional callback for structured logging (level, message)

    Returns:
        FanoutResult with outcome and details
    """
    start = datetime.now()
    command_summary = _summarize_command(command)

    def log(level: str, msg: str):
        """Structured logging with host/user context."""
        if log_callback:
            log_callback(level, msg)

    # 1. Run preflight checks
    if preflight:
        preflight_result = run_preflight_checks(host)
        if preflight_result.status != PreflightStatus.OK:
            log("WARN", f"preflight_failed host={host} status={preflight_result.status.value} "
                       f"error=\"{preflight_result.error_detail}\"")
            return FanoutResult(
                outcome=FanoutOutcome.PREFLIGHT_FAILED,
                host=host,
                user="unknown",
                command_summary=command_summary,
                exit_code=None,
                stdout=None,
                stderr=preflight_result.error_detail,
                error=preflight_result.error_detail,
                attempts=0,
                duration_ms=_elapsed_ms(start),
            )
        mapping = preflight_result.host_mapping
        log("INFO", f"preflight_ok host={host} user={mapping.user} "
                   f"auth_mode={mapping.auth_mode} duration_ms={preflight_result.duration_ms}")
    else:
        mapping = get_host_mapping(host)
        if not mapping:
            return FanoutResult(
                outcome=FanoutOutcome.PREFLIGHT_FAILED,
                host=host,
                user="unknown",
                command_summary=command_summary,
                exit_code=None,
                stdout=None,
                stderr=f"No host mapping for '{host}'",
                error=f"No host mapping for '{host}'",
                attempts=0,
                duration_ms=_elapsed_ms(start),
            )

    # 2. Build SSH command with hardened options
    ssh_opts = [
        "-o", "ConnectTimeout=10",
        "-o", "StrictHostKeyChecking=accept-new",
    ]

    if batch_mode:
        ssh_opts.extend(["-o", "BatchMode=yes"])

    # For tailscale, prefer direct connection
    if mapping.auth_mode == "tailscale":
        # Extract just the hostname for tailscale
        ssh_target = f"{mapping.user}@{mapping.hostname}"
    else:
        ssh_target = mapping.ssh_target

    full_cmd = ["ssh"] + ssh_opts + [ssh_target, command]

    # 3. Execute with bounded retry
    attempts = 0
    last_error = None
    last_exit_code = None
    last_stdout = None
    last_stderr = None

    while attempts <= max_retries:
        attempts += 1

        try:
            log("DEBUG", f"executing host={host} user={mapping.user} "
                        f"command=\"{command_summary}\" attempt={attempts}/{max_retries + 1}")

            result = subprocess.run(
                full_cmd,
                capture_output=True,
                text=True,
                timeout=timeout_sec,
            )

            last_exit_code = result.returncode
            last_stdout = _strip_ansi(result.stdout)
            last_stderr = _strip_ansi(result.stderr)

            if result.returncode == 0:
                log("INFO", f"success host={host} user={mapping.user} "
                           f"command=\"{command_summary}\" attempt={attempts} "
                           f"duration_ms={_elapsed_ms(start)}")
                return FanoutResult(
                    outcome=FanoutOutcome.SUCCESS,
                    host=host,
                    user=mapping.user,
                    command_summary=command_summary,
                    exit_code=0,
                    stdout=last_stdout,
                    stderr=last_stderr,
                    attempts=attempts,
                    duration_ms=_elapsed_ms(start),
                )

            # Non-zero exit - determine if we should retry
            last_error = f"Exit code {result.returncode}"

            # Don't retry on authentication failures
            if "Permission denied" in result.stderr:
                log("WARN", f"auth_failed host={host} user={mapping.user} "
                           f"error=\"{last_stderr[:100]}\"")
                return FanoutResult(
                    outcome=FanoutOutcome.FAILURE,
                    host=host,
                    user=mapping.user,
                    command_summary=command_summary,
                    exit_code=last_exit_code,
                    stdout=last_stdout,
                    stderr=last_stderr,
                    error="Authentication failed",
                    attempts=attempts,
                    duration_ms=_elapsed_ms(start),
                )

            # Log retry decision
            if attempts <= max_retries:
                log("WARN", f"retry host={host} user={mapping.user} "
                           f"exit_code={last_exit_code} attempt={attempts}/{max_retries + 1}")

        except subprocess.TimeoutExpired:
            last_error = f"Timeout after {timeout_sec}s"
            last_exit_code = -1

            if attempts <= max_retries:
                log("WARN", f"timeout host={host} user={mapping.user} "
                           f"timeout_sec={timeout_sec} attempt={attempts}/{max_retries + 1}")

        except Exception as e:
            last_error = str(e)
            last_exit_code = -1

            if attempts <= max_retries:
                log("WARN", f"error host={host} user={mapping.user} "
                           f"error=\"{last_error[:100]}\" attempt={attempts}/{max_retries + 1}")

        # Delay before retry
        if attempts <= max_retries:
            import time
            time.sleep(retry_delay_sec)

    # All retries exhausted - terminal failure
    log("ERROR", f"failure host={host} user={mapping.user} "
               f"command=\"{command_summary}\" final_error=\"{last_error}\" "
               f"attempts={attempts} duration_ms={_elapsed_ms(start)}")

    outcome = FanoutOutcome.TIMEOUT if "Timeout" in str(last_error) else FanoutOutcome.FAILURE

    return FanoutResult(
        outcome=outcome,
        host=host,
        user=mapping.user,
        command_summary=command_summary,
        exit_code=last_exit_code,
        stdout=last_stdout,
        stderr=last_stderr,
        error=last_error,
        attempts=attempts,
        duration_ms=_elapsed_ms(start),
    )


# Convenience function for simple dispatch
def dispatch_command(
    host: str,
    command: str,
    timeout_sec: float = 60.0,
) -> tuple[bool, str]:
    """Simple dispatch interface returning (success, output_or_error).

    For use cases that don't need full FanoutResult details.
    """
    result = fanout_ssh(host, command, timeout_sec=timeout_sec)

    if result.outcome == FanoutOutcome.SUCCESS:
        return (True, result.stdout or "")
    else:
        return (False, result.error or result.stderr or "Unknown error")
