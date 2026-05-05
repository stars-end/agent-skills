from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from lib.codex_session_repair import RepairConfig, run, sanitize_value, scan_file


def write_jsonl(path: Path, rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row) + "\n")


def test_sanitize_value_replaces_image_item_and_collapses_large_string() -> None:
    counts = {
        "image_items_replaced": 0,
        "data_image_subs": 0,
        "big_strings_collapsed": 0,
    }
    huge = "x" * 600_000
    value = {
        "content": [
            {"type": "input_image", "image_url": "data:image/png;base64,AAAA"},
            {"type": "input_text", "text": huge},
        ]
    }
    cleaned = sanitize_value(value, "", 500_000, counts)
    assert cleaned["content"][0]["type"] == "input_text"
    assert "image omitted" in cleaned["content"][0]["text"]
    assert "omitted oversized text payload" in cleaned["content"][1]["text"]
    assert counts == {
        "image_items_replaced": 1,
        "data_image_subs": 0,
        "big_strings_collapsed": 1,
    }


def test_run_repairs_candidate_and_creates_backup(tmp_path: Path) -> None:
    root = tmp_path / "sessions"
    root.mkdir()
    path = root / "rollout-test.jsonl"
    big_data = "data:image/png;base64," + ("A" * 1_500_000)
    write_jsonl(
        path,
        [
            {
                "timestamp": "2026-05-05T00:00:00Z",
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "content": [
                        {"type": "input_image", "image_url": big_data},
                    ],
                },
            }
        ],
    )

    cfg = RepairConfig(
        root=root,
        backup_root=tmp_path / "backups",
        repair=True,
        recent_hours=0,
        report_path=tmp_path / "report.json",
    )
    result = run(cfg)
    assert result.scanned_files == 1
    assert result.candidate_files == 1
    assert result.repaired_files == 1
    report = result.results[0]
    assert report.backup_path is not None
    assert Path(report.backup_path).exists()
    assert report.after is not None
    assert report.after.image_url_lines == 0
    assert report.after.big_lines_gt_threshold == 0
    repaired_text = path.read_text(encoding="utf-8")
    assert "image omitted during Codex recovery" in repaired_text


def test_recent_files_are_skipped(tmp_path: Path) -> None:
    root = tmp_path / "sessions"
    root.mkdir()
    path = root / "rollout-test.jsonl"
    write_jsonl(
        path,
        [
            {
                "timestamp": "2026-05-05T00:00:00Z",
                "type": "response_item",
                "payload": {"type": "message", "content": [{"type": "input_image", "image_url": "data:image/png;base64,AAAA"}]},
            }
        ],
    )
    cfg = RepairConfig(
        root=root,
        backup_root=tmp_path / "backups",
        repair=True,
        recent_hours=24,
    )
    result = run(cfg)
    assert result.results[0].skipped_reason == "recent<24h"
    assert list((tmp_path / "backups").rglob("*.bak-*")) == []
