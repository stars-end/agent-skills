#!/usr/bin/env python3
"""Aggregate goal-seeking eval slice results."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any


APPROVED_PREFIX = "approved"
NONE_BLOCKERS = {"", "none", "null", "approved"}


def load_payload(path: str) -> dict[str, Any]:
    data = json.loads(Path(path).read_text())
    if isinstance(data, list):
        return {"slices": data}
    if isinstance(data, dict):
        return data
    raise SystemExit("input must be a JSON object or list")


def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, tuple):
        return list(value)
    return [value]


def as_text_list(value: Any) -> list[str]:
    return [str(item).strip() for item in as_list(value) if str(item).strip()]


def score_for(item: dict[str, Any], idx: int) -> float:
    score = item.get("scalar_score", item.get("score"))
    if not isinstance(score, int | float):
        raise SystemExit(f"slice {idx} missing numeric scalar_score or score")
    return float(score)


def normalize_slice(item: dict[str, Any], idx: int) -> dict[str, Any]:
    score = score_for(item, idx)
    hard_gate_failures = as_text_list(item.get("hard_gate_failures"))
    failing_criteria = as_text_list(item.get("failing_criteria"))
    dominant_blocker = str(item.get("dominant_blocker") or "").strip()
    if not dominant_blocker:
        if hard_gate_failures:
            dominant_blocker = hard_gate_failures[0]
        elif failing_criteria:
            dominant_blocker = failing_criteria[0]
        else:
            dominant_blocker = "none"

    return {
        "slice_id": item.get("slice_id", idx),
        "passed": bool(item.get("passed", False)),
        "scalar_score": score,
        "dimension_scores": item.get("dimension_scores", item.get("dimensions", {})),
        "verdict": str(item.get("verdict", "unknown")),
        "hard_gate_failures": hard_gate_failures,
        "failing_criteria": failing_criteria,
        "dominant_blocker": dominant_blocker,
        "candidate_next_mutation_target": item.get("candidate_next_mutation_target"),
    }


def dominant_counter_value(counter: Counter[str]) -> str:
    for value, _count in counter.most_common():
        if value.lower() not in NONE_BLOCKERS:
            return value
    return "none"


def main() -> int:
    parser = argparse.ArgumentParser(description="Aggregate eval slice scores")
    parser.add_argument("input_json")
    parser.add_argument("--min-average", type=float, default=None)
    parser.add_argument("--min-approved", type=int, default=None)
    parser.add_argument("--min-passed", type=int, default=None)
    parser.add_argument("--max-unclassified", type=int, default=None)
    parser.add_argument("--require-no-hard-gates", action="store_true")
    parser.add_argument("--require-no-failing-criteria", action="store_true")
    args = parser.parse_args()

    payload = load_payload(args.input_json)
    raw_slices = payload.get("slices")
    if not isinstance(raw_slices, list) or not raw_slices:
        raise SystemExit("payload must contain non-empty slices list")

    slices = [
        normalize_slice(item, idx)
        for idx, item in enumerate(raw_slices)
        if isinstance(item, dict)
    ]
    if len(slices) != len(raw_slices):
        raise SystemExit("all slices must be objects")

    scores = [float(item["scalar_score"]) for item in slices]
    average = sum(scores) / len(scores)
    verdict_counts: Counter[str] = Counter(str(item["verdict"]) for item in slices)
    blocker_counts: Counter[str] = Counter(str(item["dominant_blocker"]) for item in slices)
    target_counts: Counter[str] = Counter(
        str(item["candidate_next_mutation_target"])
        for item in slices
        if item.get("candidate_next_mutation_target")
    )
    criteria_counts: Counter[str] = Counter(
        criterion
        for item in slices
        for criterion in item["failing_criteria"]
    )
    hard_gate_failures = [
        {"slice_id": item["slice_id"], "failures": item["hard_gate_failures"]}
        for item in slices
        if item["hard_gate_failures"]
    ]
    failing_criteria = [
        {"slice_id": item["slice_id"], "criteria": item["failing_criteria"]}
        for item in slices
        if item["failing_criteria"]
    ]

    approved = sum(
        count for verdict, count in verdict_counts.items() if verdict.startswith(APPROVED_PREFIX)
    )
    passed_count = sum(1 for item in slices if item["passed"])
    unclassified_count = verdict_counts.get("unclassified_failure", 0) + blocker_counts.get(
        "unclassified_failure", 0
    )

    min_average = args.min_average if args.min_average is not None else payload.get("min_average")
    min_approved = args.min_approved if args.min_approved is not None else payload.get("min_approved")
    min_passed = args.min_passed if args.min_passed is not None else payload.get("min_passed")
    max_unclassified = (
        args.max_unclassified
        if args.max_unclassified is not None
        else payload.get("max_unclassified")
    )

    passed = True
    reasons: list[str] = []
    if min_average is not None and average < float(min_average):
        passed = False
        reasons.append(f"average {average:.2f} < min_average {float(min_average):.2f}")
    if min_approved is not None and approved < int(min_approved):
        passed = False
        reasons.append(f"approved {approved} < min_approved {int(min_approved)}")
    if min_passed is not None and passed_count < int(min_passed):
        passed = False
        reasons.append(f"passed {passed_count} < min_passed {int(min_passed)}")
    if args.require_no_hard_gates and hard_gate_failures:
        passed = False
        reasons.append("hard gate failures present")
    if args.require_no_failing_criteria and failing_criteria:
        passed = False
        reasons.append("failing criteria present")
    if max_unclassified is not None and unclassified_count > int(max_unclassified):
        passed = False
        reasons.append(f"unclassified {unclassified_count} > max_unclassified {int(max_unclassified)}")

    dominant_blocker = dominant_counter_value(blocker_counts)
    result = {
        "passed": passed,
        "scalar_score": round(average, 3),
        "average_score": round(average, 3),
        "slice_count": len(slices),
        "passed_count": passed_count,
        "approved_count": approved,
        "verdict_counts": dict(sorted(verdict_counts.items())),
        "dominant_blocker": dominant_blocker,
        "dominant_blocker_counts": dict(sorted(blocker_counts.items())),
        "candidate_next_mutation_target_counts": dict(sorted(target_counts.items())),
        "failing_criteria": failing_criteria,
        "failing_criteria_counts": dict(sorted(criteria_counts.items())),
        "hard_gate_failures": hard_gate_failures,
        "unclassified_count": unclassified_count,
        "cycles_used": payload.get("cycles_used"),
        "max_cycles": payload.get("max_cycles"),
        "budget_exhausted": bool(payload.get("budget_exhausted", False)),
        "reasons": reasons,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
