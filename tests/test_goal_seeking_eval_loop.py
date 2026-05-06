from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AGGREGATE = ROOT / "extended" / "goal-seeking-eval-loop" / "scripts" / "aggregate_scores.py"


def run_aggregate(tmp_path: Path, payload: dict, *args: str) -> subprocess.CompletedProcess[str]:
    input_path = tmp_path / "results.json"
    input_path.write_text(json.dumps(payload), encoding="utf-8")
    return subprocess.run(
        [sys.executable, str(AGGREGATE), str(input_path), *args],
        check=False,
        text=True,
        capture_output=True,
    )


def test_aggregate_emits_single_gate_fields(tmp_path: Path) -> None:
    result = run_aggregate(
        tmp_path,
        {
            "max_cycles": 10,
            "cycles_used": 2,
            "slices": [
                {
                    "slice_id": "case-001",
                    "passed": False,
                    "scalar_score": 72,
                    "dimension_scores": {"analysis": 10},
                    "verdict": "blocked",
                    "hard_gate_failures": [],
                    "failing_criteria": ["analysis_below_threshold"],
                    "dominant_blocker": "analysis_gap",
                    "candidate_next_mutation_target": "analysis",
                }
            ],
        },
        "--min-average",
        "80",
    )

    assert result.returncode == 1
    output = json.loads(result.stdout)
    assert output["passed"] is False
    assert output["scalar_score"] == 72
    assert output["dominant_blocker"] == "analysis_gap"
    assert output["failing_criteria"] == [
        {"slice_id": "case-001", "criteria": ["analysis_below_threshold"]}
    ]
    assert output["candidate_next_mutation_target_counts"] == {"analysis": 1}
    assert output["cycles_used"] == 2
    assert output["max_cycles"] == 10


def test_aggregate_can_require_no_failing_criteria(tmp_path: Path) -> None:
    result = run_aggregate(
        tmp_path,
        {
            "slices": [
                {
                    "slice_id": "case-001",
                    "passed": True,
                    "score": 90,
                    "verdict": "approved",
                    "hard_gate_failures": [],
                    "failing_criteria": [],
                    "dominant_blocker": "none",
                }
            ]
        },
        "--min-average",
        "80",
        "--min-approved",
        "1",
        "--min-passed",
        "1",
        "--require-no-hard-gates",
        "--require-no-failing-criteria",
        "--max-unclassified",
        "0",
    )

    assert result.returncode == 0
    output = json.loads(result.stdout)
    assert output["passed"] is True
    assert output["approved_count"] == 1
    assert output["passed_count"] == 1
    assert output["failing_criteria"] == []
    assert output["hard_gate_failures"] == []
