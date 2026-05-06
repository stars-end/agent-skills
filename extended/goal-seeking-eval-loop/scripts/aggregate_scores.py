#!/usr/bin/env python3
"""Aggregate goal-seeking eval slice results.

Input JSON may be either:

[
  {"slice_id": "a", "score": 80, "verdict": "approved", "hard_gate_failures": []}
]

or:

{
  "eval_set_version": "evs-001",
  "slices": [...],
  "min_average": 75,
  "min_approved": 3
}

If a slice omits "score" but has numeric "dimensions", the score is computed
from the dimension sum. If both are present, they must match.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


APPROVED_PREFIX = "approved"
UNKNOWN = "unknown"


class InputError(ValueError):
    """Raised when the result payload is malformed."""


def load_payload(path: str) -> dict[str, Any]:
    try:
        data = json.loads(Path(path).read_text())
    except json.JSONDecodeError as exc:
        raise InputError(f"invalid JSON: {exc}") from exc
    if isinstance(data, list):
        return {"slices": data}
    if isinstance(data, dict):
        return data
    raise InputError("input must be a JSON object or list")


def normalize_label(value: Any, *, default: str = UNKNOWN) -> str:
    if value is None:
        return default
    text = str(value).strip()
    return text if text else default


def numeric(value: Any, *, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InputError(f"{label} must be numeric")
    return float(value)


def score_for_slice(item: dict[str, Any], idx: int) -> float:
    score = item.get("score")
    dimensions = item.get("dimensions")

    dimension_sum: float | None = None
    if dimensions is not None:
        if not isinstance(dimensions, dict) or not dimensions:
            raise InputError(f"slice {idx} dimensions must be a non-empty object")
        dimension_sum = sum(
            numeric(value, label=f"slice {idx} dimension {name!r}")
            for name, value in dimensions.items()
        )

    if score is None:
        if dimension_sum is None:
            raise InputError(f"slice {idx} missing numeric score or dimensions")
        return dimension_sum

    score_value = numeric(score, label=f"slice {idx} score")
    if dimension_sum is not None and abs(score_value - dimension_sum) > 0.001:
        raise InputError(
            f"slice {idx} score {score_value:.3f} != dimensions sum {dimension_sum:.3f}"
        )
    return score_value


def main() -> int:
    parser = argparse.ArgumentParser(description="Aggregate eval slice scores")
    parser.add_argument("input_json")
    parser.add_argument("--min-average", type=float, default=None)
    parser.add_argument("--min-approved", type=int, default=None)
    parser.add_argument("--require-no-hard-gates", action="store_true")
    parser.add_argument("--require-eval-version", default=None)
    args = parser.parse_args()

    try:
        payload = load_payload(args.input_json)
    except InputError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if args.require_eval_version is not None:
        eval_set_version = payload.get("eval_set_version")
        if eval_set_version != args.require_eval_version:
            print(
                "ERROR: eval_set_version "
                f"{eval_set_version!r} != required {args.require_eval_version!r}",
                file=sys.stderr,
            )
            return 2

    slices = payload.get("slices")
    if not isinstance(slices, list) or not slices:
        print("ERROR: payload must contain non-empty slices list", file=sys.stderr)
        return 2

    scores: list[float] = []
    hard_gate_failures: list[dict[str, Any]] = []
    verdict_counts: dict[str, int] = {}
    blocker_counts: dict[str, int] = {}

    try:
        for idx, item in enumerate(slices):
            if not isinstance(item, dict):
                raise InputError(f"slice {idx} must be an object")
            scores.append(score_for_slice(item, idx))

            verdict = normalize_label(item.get("verdict"))
            verdict_counts[verdict] = verdict_counts.get(verdict, 0) + 1

            blocker = normalize_label(item.get("dominant_blocker"), default="none")
            blocker_counts[blocker] = blocker_counts.get(blocker, 0) + 1

            failures = item.get("hard_gate_failures") or []
            if failures:
                hard_gate_failures.append(
                    {
                        "slice_id": item.get("slice_id", idx),
                        "failures": failures,
                    }
                )
    except InputError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    average = sum(scores) / len(scores)
    approved = sum(
        count for verdict, count in verdict_counts.items() if verdict.startswith(APPROVED_PREFIX)
    )

    min_average = args.min_average
    if min_average is None:
        min_average = payload.get("min_average")
    min_approved = args.min_approved
    if min_approved is None:
        min_approved = payload.get("min_approved")

    pass_fail = True
    reasons: list[str] = []
    if min_average is not None and average < float(min_average):
        pass_fail = False
        reasons.append(f"average {average:.2f} < min_average {float(min_average):.2f}")
    if min_approved is not None and approved < int(min_approved):
        pass_fail = False
        reasons.append(f"approved {approved} < min_approved {int(min_approved)}")
    if args.require_no_hard_gates and hard_gate_failures:
        pass_fail = False
        reasons.append("hard gate failures present")

    result = {
        "passed": pass_fail,
        "eval_set_version": payload.get("eval_set_version"),
        "average_score": round(average, 3),
        "slice_count": len(slices),
        "approved_count": approved,
        "verdict_counts": verdict_counts,
        "dominant_blocker_counts": blocker_counts,
        "hard_gate_failures": hard_gate_failures,
        "reasons": reasons,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if pass_fail else 1


if __name__ == "__main__":
    sys.exit(main())
