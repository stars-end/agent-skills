"""Reason-code parity tests for dx-batch status/check/report."""

import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from dx_batch import (
    WaveConfig,
    WaveOrchestrator,
    WaveStatus,
    ItemStatus,
    cmd_check,
    cmd_report,
    cmd_status,
)


class TestReasonCodes:
    def test_status_json_includes_wave_and_item_reason_codes(self, tmp_path, capsys):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            orchestrator = WaveOrchestrator("reason-status-test", WaveConfig())
            orchestrator.create_wave(["bd-rsn.1"])
            state = orchestrator.load_state()
            state.status = WaveStatus.FAILED
            state.reason_code = "exec_saturation"
            state.items[0].status = ItemStatus.BLOCKED
            state.items[0].reason_code = "retry_chain_exhausted"
            orchestrator.state = state
            orchestrator.save_state()

            rc = cmd_status(SimpleNamespace(wave_id="reason-status-test", json=True))
            out = capsys.readouterr().out
            payload = json.loads(out)

            assert rc == 0
            assert payload["reason_code"] == "exec_saturation"
            assert payload["items"][0]["reason_code"] == "retry_chain_exhausted"
            assert payload["next_action"] == "run_dx_runner_prune_then_dx_batch_doctor"

    def test_check_exit_codes_and_reason_codes(self, tmp_path, capsys):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            # Missing wave -> rc 3
            rc_missing = cmd_check(SimpleNamespace(wave_id="missing-wave", json=True))
            missing_payload = json.loads(capsys.readouterr().out)
            assert rc_missing == 3
            assert missing_payload["reason_code"] == "wave_not_found"

            # Paused wave -> rc 2
            orchestrator = WaveOrchestrator("reason-check-test", WaveConfig())
            orchestrator.create_wave(["bd-rsn.2"])
            state = orchestrator.load_state()
            state.status = WaveStatus.PAUSED
            state.reason_code = "wave_paused_signal"
            orchestrator.state = state
            orchestrator.save_state()

            rc_paused = cmd_check(
                SimpleNamespace(wave_id="reason-check-test", json=True)
            )
            paused_payload = json.loads(capsys.readouterr().out)
            assert rc_paused == 2
            assert paused_payload["reason_code"] == "wave_paused_signal"

    def test_report_json_includes_reason_codes(self, tmp_path, capsys):
        with patch("dx_batch.ARTIFACT_BASE", tmp_path):
            orchestrator = WaveOrchestrator("reason-report-test", WaveConfig())
            orchestrator.create_wave(["bd-rsn.3"])
            state = orchestrator.load_state()
            state.status = WaveStatus.COMPLETED
            state.reason_code = "wave_completed"
            state.items[0].status = ItemStatus.APPROVED
            state.items[0].reason_code = "approved"
            orchestrator.state = state
            orchestrator.save_state()

            rc = cmd_report(
                SimpleNamespace(wave_id="reason-report-test", format="json")
            )
            out = capsys.readouterr().out
            payload = json.loads(out)

            assert rc == 0
            assert payload["reason_code"] == "wave_completed"
            assert payload["items"][0]["reason_code"] == "approved"
