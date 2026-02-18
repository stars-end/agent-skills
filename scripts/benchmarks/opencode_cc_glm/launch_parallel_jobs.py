#!/usr/bin/env python3
"""Launch reproducible parallel benchmark jobs for cc-glm vs OpenCode."""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import dataclasses
import datetime as dt
import hashlib
import json
import os
import pathlib
import queue
import random
import re
import selectors
import subprocess
import threading
import time
import urllib.error
import urllib.request
from typing import Any

WORKFLOW_SYSTEM = {
    "cc_glm_headless": "cc-glm",
    "opencode_run_headless": "opencode",
    "opencode_server_http": "opencode",
    "opencode_server_attach_run": "opencode",
    "gemini_run_headless": "gemini",
}

SERVER_WORKFLOWS = {"opencode_server_http", "opencode_server_attach_run"}
ALL_WORKFLOWS = tuple(WORKFLOW_SYSTEM.keys())

REDACT_PATTERNS = [
    re.compile(r"op://[^\s\"']+"),
    re.compile(r"(?i)authorization\s*:\s*bearer\s+[a-z0-9._\-]+"),
    re.compile(r"\bsk-[A-Za-z0-9]{12,}\b"),
    re.compile(r"\bZAI[A-Za-z0-9_\-]{8,}\b"),
    re.compile(r"\bOP_SERVICE_ACCOUNT_TOKEN\b\s*=\s*[^\s]+"),
]


def utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sanitize_text(value: str) -> str:
    text = value
    for pattern in REDACT_PATTERNS:
        text = pattern.sub("[REDACTED]", text)
    return text


def http_json(
    base_url: str,
    path: str,
    *,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
    timeout_sec: float = 30.0,
    password: str | None = None,
) -> Any:
    url = f"{base_url.rstrip('/')}/{path.lstrip('/')}"
    headers: dict[str, str] = {"Accept": "application/json"}
    body: bytes | None = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if password:
        token = base64.b64encode(f":{password}".encode("utf-8")).decode("ascii")
        headers["Authorization"] = f"Basic {token}"

    request = urllib.request.Request(url, data=body, method=method, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout_sec) as response:
        raw = response.read().decode("utf-8", errors="replace")
    if not raw.strip():
        return {}
    return json.loads(raw)


@dataclasses.dataclass(frozen=True)
class PromptCase:
    prompt_id: str
    category: str
    title: str
    prompt: str
    success_hints: list[str]


@dataclasses.dataclass(frozen=True)
class JobSpec:
    run_id: str
    workflow_id: str
    prompt: PromptCase
    model: str
    output_dir: pathlib.Path
    cwd: pathlib.Path


class OpenCodeServerProcess:
    def __init__(
        self,
        *,
        workflow_id: str,
        host: str,
        port: int,
        output_dir: pathlib.Path,
        timeout_sec: float,
        password: str | None,
        opencode_bin: str,
    ):
        self.workflow_id = workflow_id
        self.host = host
        self.port = port
        self.output_dir = output_dir
        self.timeout_sec = timeout_sec
        self.password = password
        self.opencode_bin = opencode_bin
        self.process: subprocess.Popen[str] | None = None
        self.startup_latency_ms: int | None = None
        self.log_path = self.output_dir / f"{workflow_id}__server.log"

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}"

    def start(self) -> None:
        start = time.perf_counter()
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        log_handle = self.log_path.open("w", encoding="utf-8")
        cmd = [
            self.opencode_bin,
            "serve",
            "--hostname",
            self.host,
            "--port",
            str(self.port),
            "--print-logs",
        ]
        self.process = subprocess.Popen(
            cmd,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            text=True,
            cwd=str(pathlib.Path.cwd()),
            env=os.environ.copy(),
        )

        deadline = time.perf_counter() + self.timeout_sec
        last_error = ""
        while time.perf_counter() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError(
                    f"opencode serve exited early for {self.workflow_id}; see {self.log_path}"
                )
            try:
                payload = http_json(
                    self.base_url,
                    "/global/health",
                    timeout_sec=2.0,
                    password=self.password,
                )
                healthy = bool(payload.get("healthy") is True or payload.get("status") == "ok")
                if healthy:
                    self.startup_latency_ms = int((time.perf_counter() - start) * 1000)
                    return
            except Exception as exc:  # noqa: BLE001
                last_error = str(exc)
            time.sleep(0.25)
        raise RuntimeError(
            f"timeout waiting for opencode health on {self.base_url}; last_error={last_error}"
        )

    def stop(self) -> None:
        if self.process is None:
            return
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)



def load_prompts(path: pathlib.Path) -> list[PromptCase]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    prompts = []
    for item in payload["prompts"]:
        prompts.append(
            PromptCase(
                prompt_id=item["id"],
                category=item["category"],
                title=item["title"],
                prompt=item["prompt"],
                success_hints=list(item.get("success_hints", [])),
            )
        )
    return prompts



def parse_model_string(model: str) -> dict[str, str]:
    """Convert provider/model string into OpenCode API model object."""
    if "/" in model:
        provider_id, model_id = model.split("/", 1)
        return {"providerID": provider_id, "modelID": model_id}
    return {"modelID": model}



def run_subprocess_capture(
    cmd: list[str],
    *,
    cwd: pathlib.Path,
    env: dict[str, str],
    timeout_sec: float,
) -> dict[str, Any]:
    start = time.perf_counter()
    spawn_start = time.perf_counter()
    process = subprocess.Popen(
        cmd,
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        errors="replace",
        bufsize=1,
    )
    spawn_end = time.perf_counter()

    stdout_lines: list[str] = []
    stderr_lines: list[str] = []
    first_output_at: float | None = None

    sel = selectors.DefaultSelector()
    assert process.stdout is not None
    assert process.stderr is not None
    sel.register(process.stdout, selectors.EVENT_READ, data="stdout")
    sel.register(process.stderr, selectors.EVENT_READ, data="stderr")

    timed_out = False
    try:
        while sel.get_map():
            elapsed = time.perf_counter() - start
            if elapsed > timeout_sec:
                timed_out = True
                process.kill()
                break

            events = sel.select(timeout=0.1)
            if not events and process.poll() is not None:
                break
            for key, _ in events:
                stream = key.fileobj
                line = stream.readline()
                if line == "":
                    try:
                        sel.unregister(stream)
                    except Exception:  # noqa: BLE001
                        pass
                    continue
                if first_output_at is None:
                    first_output_at = time.perf_counter()
                if key.data == "stdout":
                    stdout_lines.append(line)
                else:
                    stderr_lines.append(line)
    finally:
        try:
            sel.close()
        except Exception:  # noqa: BLE001
            pass

    try:
        return_code = process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        return_code = process.wait(timeout=5)

    end = time.perf_counter()
    completion_latency_ms = int((end - start) * 1000)
    startup_latency_ms = int((spawn_end - spawn_start) * 1000)
    first_output_latency_ms = (
        int((first_output_at - start) * 1000) if first_output_at is not None else None
    )

    return {
        "return_code": return_code,
        "timed_out": timed_out,
        "startup_latency_ms": startup_latency_ms,
        "first_output_latency_ms": first_output_latency_ms,
        "completion_latency_ms": completion_latency_ms,
        "stdout": sanitize_text("".join(stdout_lines)),
        "stderr": sanitize_text("".join(stderr_lines)),
    }



def extract_text_from_messages(messages_payload: Any) -> str:
    if isinstance(messages_payload, dict):
        if isinstance(messages_payload.get("messages"), list):
            messages = messages_payload["messages"]
        elif isinstance(messages_payload.get("items"), list):
            messages = messages_payload["items"]
        else:
            messages = []
    elif isinstance(messages_payload, list):
        messages = messages_payload
    else:
        messages = []

    chunks: list[str] = []
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        parts = msg.get("parts", [])
        if not isinstance(parts, list):
            continue
        for part in parts:
            if not isinstance(part, dict):
                continue
            if part.get("type") == "text" and isinstance(part.get("text"), str):
                chunks.append(part["text"])
    return sanitize_text("\n".join(chunks)).strip()



def classify_failure(
    *,
    success: bool,
    exception_text: str | None,
    return_code: int | None,
    timed_out: bool,
    stdout: str,
    stderr: str,
) -> tuple[str | None, str | None]:
    if success:
        return None, None

    if exception_text:
        lowered = exception_text.lower()
        env_markers = ["connection", "refused", "not found", "auth", "permission", "timeout"]
        if any(marker in lowered for marker in env_markers):
            return "env", "exception_env"
        return "harness", "exception_harness"

    lowered = f"{stdout}\n{stderr}".lower()
    env_patterns = [
        "command not found",
        "no such file",
        "unable to resolve",
        "unauthorized",
        "forbidden",
        "api key",
        "auth",
        "ecconnrefused",
        "connection refused",
        "exhausted your capacity",
        "quota",
        "rate limit",
    ]
    if return_code == 127 or any(marker in lowered for marker in env_patterns):
        return "env", "runtime_env"
    if timed_out:
        return "model", "timeout"
    if return_code is not None and return_code != 0:
        return "model", "runtime_nonzero"
    return "harness", "empty_or_unknown"



def hint_match_ratio(output: str, hints: list[str]) -> float:
    if not hints:
        return 1.0
    lowered = output.lower()
    matched = 0
    for hint in hints:
        if hint.lower() in lowered:
            matched += 1
    return matched / len(hints)



def parse_opencode_json_stream(output: str) -> tuple[list[str], str]:
    """Parse opencode --format json output into (errors, extracted_text)."""
    errors: list[str] = []
    text_chunks: list[str] = []

    for line in output.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue

        if isinstance(event.get("error"), dict):
            msg = (
                event["error"].get("message")
                or (event["error"].get("data") or {}).get("message")
                or str(event["error"])
            )
            if msg:
                errors.append(str(msg))

        for key in ("text", "message", "content", "output"):
            value = event.get(key)
            if isinstance(value, str) and value.strip():
                text_chunks.append(value)

        parts = event.get("parts")
        if isinstance(parts, list):
            for part in parts:
                if (
                    isinstance(part, dict)
                    and part.get("type") == "text"
                    and isinstance(part.get("text"), str)
                ):
                    text_chunks.append(part["text"])

    return errors, sanitize_text("\n".join(text_chunks)).strip()


def parse_gemini_json_output(output: str) -> tuple[str, list[str]]:
    """Parse Gemini JSON output into (response_text, non-fatal notices/errors)."""
    notices: list[str] = []
    payload: dict[str, Any] | None = None

    raw = output.strip()
    if not raw:
        return "", notices

    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            payload = parsed
    except json.JSONDecodeError:
        start = raw.find("{")
        end = raw.rfind("}")
        if start >= 0 and end > start:
            snippet = raw[start : end + 1]
            try:
                parsed = json.loads(snippet)
                if isinstance(parsed, dict):
                    payload = parsed
            except json.JSONDecodeError:
                payload = None

    if payload is None:
        return "", notices

    response_text = payload.get("response")
    if not isinstance(response_text, str):
        response_text = ""

    stats = payload.get("stats")
    if isinstance(stats, dict):
        models = stats.get("models")
        if isinstance(models, dict):
            for _, model_stats in models.items():
                if not isinstance(model_stats, dict):
                    continue
                api_stats = model_stats.get("api")
                if isinstance(api_stats, dict):
                    total_errors = api_stats.get("totalErrors")
                    if isinstance(total_errors, int) and total_errors > 0:
                        notices.append(f"gemini_api_total_errors={total_errors}")

    return sanitize_text(response_text), notices


def dry_run_attempt(job: JobSpec, attempt: int) -> dict[str, Any]:
    key = f"{job.run_id}:{job.workflow_id}:{job.prompt.prompt_id}:{attempt}"
    seed = int(hashlib.sha256(key.encode("utf-8")).hexdigest()[:8], 16)
    rng = random.Random(seed)

    base_completion = 700 + (seed % 2200)
    startup = 20 + (seed % 90)
    first_output = startup + 100 + (seed % 700)

    fail_first_try = (seed % 7 == 0) and attempt == 0
    success = not fail_first_try
    if not success:
        failure_bucket = ["harness", "model", "env"][seed % 3]
        return_code = [2, 1, 127][seed % 3]
        stderr = f"dry-run simulated {failure_bucket} failure"
        stdout = ""
    else:
        failure_bucket = None
        return_code = 0
        stderr = ""
        stdout = (
            f"dry-run output run_id={job.run_id} workflow_id={job.workflow_id} "
            f"prompt_id={job.prompt.prompt_id}"
        )

    return {
        "success": success,
        "return_code": return_code,
        "timed_out": False,
        "startup_latency_ms": startup,
        "first_output_latency_ms": first_output,
        "completion_latency_ms": base_completion,
        "stdout": stdout,
        "stderr": stderr,
        "failure_category": failure_bucket,
        "failure_reason": "dry_run_simulated" if failure_bucket else None,
        "hint_match_ratio": hint_match_ratio(stdout, job.prompt.success_hints),
        "session_id": None,
        "used_model_fallback": False,
    }



def execute_http_workflow(
    job: JobSpec,
    *,
    base_url: str,
    timeout_sec: float,
    poll_interval_sec: float,
    password: str | None,
) -> dict[str, Any]:
    start = time.perf_counter()
    exception_text: str | None = None
    used_model_fallback = False
    session_id: str | None = None

    try:
        created = http_json(
            base_url,
            "/session",
            method="POST",
            payload={"title": f"{job.run_id}:{job.workflow_id}:{job.prompt.prompt_id}"},
            timeout_sec=timeout_sec,
            password=password,
        )
        session_id = created.get("id")
        if not session_id:
            raise RuntimeError(f"missing session id in create response: {created}")

        payload = {
            "parts": [{"type": "text", "text": job.prompt.prompt}],
            "model": parse_model_string(job.model),
        }
        try:
            http_json(
                base_url,
                f"/session/{session_id}/prompt_async",
                method="POST",
                payload=payload,
                timeout_sec=timeout_sec,
                password=password,
            )
        except Exception:
            used_model_fallback = True
            payload.pop("model", None)
            http_json(
                base_url,
                f"/session/{session_id}/prompt_async",
                method="POST",
                payload=payload,
                timeout_sec=timeout_sec,
                password=password,
            )

        first_output_at: float | None = None
        assistant_text = ""
        idle_rounds = 0
        deadline = time.perf_counter() + timeout_sec

        while time.perf_counter() < deadline:
            status_payload = http_json(
                base_url,
                "/session/status",
                method="GET",
                timeout_sec=timeout_sec,
                password=password,
            )
            busy = bool(isinstance(status_payload, dict) and session_id in status_payload)

            messages_payload = http_json(
                base_url,
                f"/session/{session_id}/message",
                method="GET",
                timeout_sec=timeout_sec,
                password=password,
            )
            assistant_text = extract_text_from_messages(messages_payload)

            if assistant_text and first_output_at is None:
                first_output_at = time.perf_counter()

            if not busy:
                idle_rounds += 1
            else:
                idle_rounds = 0

            if not busy and assistant_text:
                break
            if not busy and idle_rounds >= 3:
                break

            time.sleep(poll_interval_sec)

        end = time.perf_counter()
        timed_out = end >= deadline and not assistant_text
        success = bool(assistant_text) and not timed_out

        first_output_latency_ms = (
            int((first_output_at - start) * 1000) if first_output_at is not None else None
        )

        category, reason = classify_failure(
            success=success,
            exception_text=None,
            return_code=0 if success else 1,
            timed_out=timed_out,
            stdout=assistant_text,
            stderr="",
        )
        if used_model_fallback and not success and category is None:
            category, reason = "model", "model_field_unsupported"

        return {
            "success": success,
            "return_code": 0 if success else 1,
            "timed_out": timed_out,
            "startup_latency_ms": 0,
            "first_output_latency_ms": first_output_latency_ms,
            "completion_latency_ms": int((end - start) * 1000),
            "stdout": assistant_text,
            "stderr": "",
            "failure_category": category,
            "failure_reason": reason,
            "hint_match_ratio": hint_match_ratio(assistant_text, job.prompt.success_hints),
            "session_id": session_id,
            "used_model_fallback": used_model_fallback,
        }
    except Exception as exc:  # noqa: BLE001
        exception_text = sanitize_text(str(exc))
        end = time.perf_counter()
        category, reason = classify_failure(
            success=False,
            exception_text=exception_text,
            return_code=None,
            timed_out=False,
            stdout="",
            stderr=exception_text,
        )
        return {
            "success": False,
            "return_code": None,
            "timed_out": False,
            "startup_latency_ms": 0,
            "first_output_latency_ms": None,
            "completion_latency_ms": int((end - start) * 1000),
            "stdout": "",
            "stderr": exception_text,
            "failure_category": category,
            "failure_reason": reason,
            "hint_match_ratio": 0.0,
            "session_id": session_id,
            "used_model_fallback": used_model_fallback,
        }



def execute_cli_workflow(
    job: JobSpec,
    *,
    workflow_id: str,
    timeout_sec: float,
    opencode_url: str | None,
    cc_glm_headless_path: pathlib.Path,
) -> dict[str, Any]:
    env = os.environ.copy()
    prompt_file = job.output_dir / "raw" / f"{job.workflow_id}__{job.prompt.prompt_id}.prompt.txt"
    prompt_file.parent.mkdir(parents=True, exist_ok=True)
    prompt_file.write_text(job.prompt.prompt, encoding="utf-8")

    if workflow_id == "cc_glm_headless":
        env["CC_GLM_MODEL"] = job.model
        cmd = [str(cc_glm_headless_path), "--prompt-file", str(prompt_file)]
    elif workflow_id == "opencode_run_headless":
        cmd = [
            "opencode",
            "run",
            "--format",
            "json",
            "--model",
            job.model,
            "--title",
            f"{job.run_id}:{job.workflow_id}:{job.prompt.prompt_id}",
            "--dir",
            str(job.cwd),
            job.prompt.prompt,
        ]
    elif workflow_id == "opencode_server_attach_run":
        if not opencode_url:
            raise RuntimeError("opencode_url is required for attach workflow")
        cmd = [
            "opencode",
            "run",
            "--attach",
            opencode_url,
            "--format",
            "json",
            "--model",
            job.model,
            "--title",
            f"{job.run_id}:{job.workflow_id}:{job.prompt.prompt_id}",
            "--dir",
            str(job.cwd),
            job.prompt.prompt,
        ]
    elif workflow_id == "gemini_run_headless":
        cmd = [
            "gemini",
            "--model",
            job.model,
            "--prompt",
            job.prompt.prompt,
            "--output-format",
            "json",
        ]
    else:
        raise RuntimeError(f"unsupported CLI workflow: {workflow_id}")

    raw = run_subprocess_capture(cmd, cwd=job.cwd, env=env, timeout_sec=timeout_sec)
    output_text = raw["stdout"] if raw["stdout"].strip() else raw["stderr"]
    output_for_hints = output_text
    classified_stdout = raw["stdout"]
    classified_stderr = raw["stderr"]
    forced_failure: tuple[str, str] | None = None

    if workflow_id.startswith("opencode_"):
        opencode_errors, parsed_text = parse_opencode_json_stream(output_text)
        if parsed_text:
            output_for_hints = parsed_text
        if opencode_errors:
            error_blob = " | ".join(opencode_errors)
            classified_stderr = sanitize_text(f"{classified_stderr}\n{error_blob}".strip())
            lowered = error_blob.lower()
            if "model not found" in lowered or "providermodelnotfounderror" in lowered:
                forced_failure = ("model", "model_not_supported")
            elif "unauthorized" in lowered or "forbidden" in lowered or "api key" in lowered:
                forced_failure = ("env", "auth_or_provider")
            else:
                forced_failure = ("model", "opencode_error_event")
    elif workflow_id == "gemini_run_headless":
        gemini_response, gemini_notices = parse_gemini_json_output(output_text)
        if gemini_response:
            output_for_hints = gemini_response
        if gemini_notices:
            classified_stderr = sanitize_text(
                f"{classified_stderr}\n{' | '.join(gemini_notices)}".strip()
            )
        if not gemini_response:
            lowered = f"{classified_stdout}\n{classified_stderr}".lower()
            if "exhausted your capacity" in lowered or "quota" in lowered:
                forced_failure = ("env", "quota_or_rate_limit")

    success = (
        raw["return_code"] == 0
        and bool(output_for_hints.strip())
        and not raw["timed_out"]
        and forced_failure is None
    )
    category, reason = classify_failure(
        success=success,
        exception_text=None,
        return_code=raw["return_code"],
        timed_out=raw["timed_out"],
        stdout=classified_stdout,
        stderr=classified_stderr,
    )
    if forced_failure is not None:
        category, reason = forced_failure
    return {
        "success": success,
        "return_code": raw["return_code"],
        "timed_out": raw["timed_out"],
        "startup_latency_ms": raw["startup_latency_ms"],
        "first_output_latency_ms": raw["first_output_latency_ms"],
        "completion_latency_ms": raw["completion_latency_ms"],
        "stdout": raw["stdout"],
        "stderr": classified_stderr,
        "failure_category": category,
        "failure_reason": reason,
        "hint_match_ratio": hint_match_ratio(output_for_hints, job.prompt.success_hints),
        "session_id": None,
        "used_model_fallback": False,
    }



def run_attempt(
    job: JobSpec,
    *,
    attempt: int,
    dry_run: bool,
    timeout_sec: float,
    poll_interval_sec: float,
    opencode_url: str | None,
    opencode_password: str | None,
    cc_glm_headless_path: pathlib.Path,
) -> dict[str, Any]:
    if dry_run:
        return dry_run_attempt(job, attempt)
    if job.workflow_id == "opencode_server_http":
        if not opencode_url:
            raise RuntimeError("opencode_url is required for opencode_server_http")
        return execute_http_workflow(
            job,
            base_url=opencode_url,
            timeout_sec=timeout_sec,
            poll_interval_sec=poll_interval_sec,
            password=opencode_password,
        )
    return execute_cli_workflow(
        job,
        workflow_id=job.workflow_id,
        timeout_sec=timeout_sec,
        opencode_url=opencode_url,
        cc_glm_headless_path=cc_glm_headless_path,
    )



def persist_attempt_logs(run_dir: pathlib.Path, job: JobSpec, attempt: int, result: dict[str, Any]) -> None:
    stem = f"{job.workflow_id}__{job.prompt.prompt_id}__attempt{attempt}"
    stdout_path = run_dir / "raw" / f"{stem}.stdout.log"
    stderr_path = run_dir / "raw" / f"{stem}.stderr.log"
    stdout_path.write_text(result.get("stdout", ""), encoding="utf-8")
    stderr_path.write_text(result.get("stderr", ""), encoding="utf-8")



def execute_job(
    job: JobSpec,
    *,
    run_dir: pathlib.Path,
    max_retries: int,
    dry_run: bool,
    timeout_sec: float,
    poll_interval_sec: float,
    opencode_url: str | None,
    opencode_password: str | None,
    cc_glm_headless_path: pathlib.Path,
    workflow_startup_latency_ms: int | None,
) -> dict[str, Any]:
    attempts: list[dict[str, Any]] = []
    job_started_at = utc_now_iso()

    for attempt in range(max_retries + 1):
        attempt_started = utc_now_iso()
        result = run_attempt(
            job,
            attempt=attempt,
            dry_run=dry_run,
            timeout_sec=timeout_sec,
            poll_interval_sec=poll_interval_sec,
            opencode_url=opencode_url,
            opencode_password=opencode_password,
            cc_glm_headless_path=cc_glm_headless_path,
        )
        attempt_completed = utc_now_iso()
        result["attempt"] = attempt
        result["attempt_started_at"] = attempt_started
        result["attempt_completed_at"] = attempt_completed
        attempts.append(result)
        persist_attempt_logs(run_dir, job, attempt, result)
        if result["success"]:
            break

    final = attempts[-1]
    record = {
        "run_id": job.run_id,
        "workflow_id": job.workflow_id,
        "system": WORKFLOW_SYSTEM[job.workflow_id],
        "workflow_kind": "server" if job.workflow_id in SERVER_WORKFLOWS else "headless",
        "prompt_id": job.prompt.prompt_id,
        "prompt_category": job.prompt.category,
        "prompt_title": job.prompt.title,
        "model": job.model,
        "success": bool(final["success"]),
        "retry_count": max(0, len(attempts) - 1),
        "startup_latency_ms": final["startup_latency_ms"],
        "first_output_latency_ms": final["first_output_latency_ms"],
        "completion_latency_ms": final["completion_latency_ms"],
        "workflow_startup_latency_ms": workflow_startup_latency_ms,
        "failure_category": final.get("failure_category"),
        "failure_reason": final.get("failure_reason"),
        "hint_match_ratio": final.get("hint_match_ratio"),
        "session_id": final.get("session_id"),
        "used_model_fallback": bool(final.get("used_model_fallback", False)),
        "job_started_at": job_started_at,
        "job_completed_at": utc_now_iso(),
        "attempts": attempts,
    }

    raw_json_path = run_dir / "raw" / f"{job.workflow_id}__{job.prompt.prompt_id}.json"
    raw_json_path.write_text(json.dumps(record, indent=2), encoding="utf-8")
    return record



def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Launch parallel benchmark jobs")
    parser.add_argument("--prompts-file", required=True, type=pathlib.Path)
    parser.add_argument("--run-id", default=f"run-{dt.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')}")
    parser.add_argument("--workflows", default=",".join(ALL_WORKFLOWS))
    parser.add_argument("--parallel", type=int, default=4)
    parser.add_argument("--model", default="glm-5")
    parser.add_argument("--output-dir", type=pathlib.Path, default=pathlib.Path("./artifacts/opencode-cc-glm-bench"))
    parser.add_argument("--max-retries", type=int, default=1)
    parser.add_argument("--timeout-sec", type=float, default=300.0)
    parser.add_argument("--poll-interval-sec", type=float, default=0.5)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--cwd", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--opencode-url", default=None)
    parser.add_argument("--opencode-host", default="127.0.0.1")
    parser.add_argument("--opencode-port", type=int, default=4096)
    parser.add_argument("--opencode-password", default=os.environ.get("OPENCODE_SERVER_PASSWORD"))
    parser.add_argument("--opencode-bin", default="opencode")
    parser.add_argument(
        "--cc-glm-headless-path",
        type=pathlib.Path,
        default=pathlib.Path("extended/cc-glm/scripts/cc-glm-headless.sh"),
    )
    return parser.parse_args()



def main() -> int:
    args = parse_args()
    workflows = [item.strip() for item in args.workflows.split(",") if item.strip()]
    unknown = [workflow for workflow in workflows if workflow not in WORKFLOW_SYSTEM]
    if unknown:
        raise SystemExit(f"Unknown workflows: {unknown}. Valid={ALL_WORKFLOWS}")

    run_dir = (args.output_dir / args.run_id).resolve()
    (run_dir / "raw").mkdir(parents=True, exist_ok=True)

    prompts = load_prompts(args.prompts_file.resolve())

    manifest = {
        "run_id": args.run_id,
        "created_at": utc_now_iso(),
        "workflows": workflows,
        "model": args.model,
        "parallel": args.parallel,
        "max_retries": args.max_retries,
        "timeout_sec": args.timeout_sec,
        "dry_run": bool(args.dry_run),
        "cwd": str(args.cwd.resolve()),
        "prompts_file": str(args.prompts_file.resolve()),
    }
    (run_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    servers: dict[str, OpenCodeServerProcess] = {}
    workflow_url: dict[str, str | None] = {}
    workflow_startup_latency: dict[str, int | None] = {workflow: None for workflow in workflows}

    try:
        server_index = 0
        for workflow_id in workflows:
            if workflow_id not in SERVER_WORKFLOWS:
                workflow_url[workflow_id] = args.opencode_url
                continue

            if args.dry_run:
                workflow_url[workflow_id] = "http://dry-run.invalid"
                workflow_startup_latency[workflow_id] = 0
                continue

            if args.opencode_url:
                workflow_url[workflow_id] = args.opencode_url
                workflow_startup_latency[workflow_id] = 0
                continue

            port = args.opencode_port + server_index
            server_index += 1
            server = OpenCodeServerProcess(
                workflow_id=workflow_id,
                host=args.opencode_host,
                port=port,
                output_dir=run_dir / "raw",
                timeout_sec=max(30.0, args.timeout_sec / 2),
                password=args.opencode_password,
                opencode_bin=args.opencode_bin,
            )
            server.start()
            servers[workflow_id] = server
            workflow_url[workflow_id] = server.base_url
            workflow_startup_latency[workflow_id] = server.startup_latency_ms

        jobs: list[JobSpec] = []
        for workflow_id in workflows:
            for prompt in prompts:
                jobs.append(
                    JobSpec(
                        run_id=args.run_id,
                        workflow_id=workflow_id,
                        prompt=prompt,
                        model=args.model,
                        output_dir=run_dir,
                        cwd=args.cwd.resolve(),
                    )
                )

        results: list[dict[str, Any]] = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.parallel)) as executor:
            future_map = {}
            for job in jobs:
                future = executor.submit(
                    execute_job,
                    job,
                    run_dir=run_dir,
                    max_retries=max(0, args.max_retries),
                    dry_run=args.dry_run,
                    timeout_sec=args.timeout_sec,
                    poll_interval_sec=max(0.1, args.poll_interval_sec),
                    opencode_url=workflow_url.get(job.workflow_id),
                    opencode_password=args.opencode_password,
                    cc_glm_headless_path=args.cc_glm_headless_path.resolve(),
                    workflow_startup_latency_ms=workflow_startup_latency.get(job.workflow_id),
                )
                future_map[future] = job

            for future in concurrent.futures.as_completed(future_map):
                job = future_map[future]
                try:
                    result = future.result()
                    results.append(result)
                except Exception as exc:  # noqa: BLE001
                    error_record = {
                        "run_id": args.run_id,
                        "workflow_id": job.workflow_id,
                        "system": WORKFLOW_SYSTEM[job.workflow_id],
                        "workflow_kind": "server" if job.workflow_id in SERVER_WORKFLOWS else "headless",
                        "prompt_id": job.prompt.prompt_id,
                        "prompt_category": job.prompt.category,
                        "prompt_title": job.prompt.title,
                        "model": job.model,
                        "success": False,
                        "retry_count": max(0, args.max_retries),
                        "startup_latency_ms": None,
                        "first_output_latency_ms": None,
                        "completion_latency_ms": None,
                        "workflow_startup_latency_ms": workflow_startup_latency.get(job.workflow_id),
                        "failure_category": "harness",
                        "failure_reason": "executor_exception",
                        "hint_match_ratio": 0.0,
                        "session_id": None,
                        "used_model_fallback": False,
                        "job_started_at": utc_now_iso(),
                        "job_completed_at": utc_now_iso(),
                        "attempts": [
                            {
                                "attempt": 0,
                                "success": False,
                                "stderr": sanitize_text(str(exc)),
                                "failure_category": "harness",
                                "failure_reason": "executor_exception",
                            }
                        ],
                    }
                    results.append(error_record)
                    path = run_dir / "raw" / f"{job.workflow_id}__{job.prompt.prompt_id}.json"
                    path.write_text(json.dumps(error_record, indent=2), encoding="utf-8")

        run_results = {
            "run_id": args.run_id,
            "generated_at": utc_now_iso(),
            "records": sorted(results, key=lambda r: (r["workflow_id"], r["prompt_id"])),
        }
        (run_dir / "run_results.json").write_text(json.dumps(run_results, indent=2), encoding="utf-8")

        print(json.dumps({"run_id": args.run_id, "run_dir": str(run_dir), "record_count": len(results)}))
        return 0
    finally:
        for server in servers.values():
            server.stop()


if __name__ == "__main__":
    raise SystemExit(main())
