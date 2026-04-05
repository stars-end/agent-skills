#!/usr/bin/env python3
"""Validate a golden CSV fixture run.

Compares output.csv against expected.csv and writes validation.json.

Usage:
    python3 validate_run.py --run-dir DIR [--template-dir DIR]

Exit code 0 if pass, 1 if fail. Writes validation.json either way.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Optional


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_TEMPLATE_DIR = SCRIPT_DIR.parent / "template"


def validate_run(run_dir: str, template_dir: Optional[str] = None) -> dict:
    rdir = Path(run_dir)
    tdir = Path(template_dir) if template_dir else REPO_TEMPLATE_DIR

    output_csv = rdir / "output.csv"
    expected_csv = tdir / "expected.csv"
    run_json = rdir / "run.json"

    errors = []

    if not output_csv.exists():
        errors.append("output.csv does not exist")

    if not expected_csv.exists():
        errors.append(f"expected.csv not found at {expected_csv}")

    if not run_json.exists():
        errors.append("run.json does not exist")

    if errors:
        result = {
            "valid": False,
            "errors": errors,
            "checks": {},
        }
    else:
        actual_lines = (
            output_csv.read_text().rstrip("\n").split("\n")
            if output_csv.exists()
            else []
        )
        expected_lines = (
            expected_csv.read_text().rstrip("\n").split("\n")
            if expected_csv.exists()
            else []
        )

        checks = {}

        checks["line_count"] = {
            "expected": len(expected_lines),
            "actual": len(actual_lines),
            "pass": len(actual_lines) == len(expected_lines),
        }

        checks["exact_order"] = {
            "pass": actual_lines == expected_lines,
        }

        checks["no_duplicates"] = {
            "pass": len(actual_lines) == len(set(actual_lines)),
        }

        checks["exact_content"] = {
            "pass": actual_lines == expected_lines,
            "expected": expected_lines,
            "actual": actual_lines,
        }

        all_pass = all(c.get("pass", False) for c in checks.values())

        spec = json.loads(run_json.read_text()).get("spec", {})
        assertions = spec.get("assertions", {})

        if assertions.get("exact_content"):
            checks["spec_assertion"] = {
                "pass": actual_lines == assertions["exact_content"],
            }
            all_pass = all_pass and checks["spec_assertion"]["pass"]

        result = {
            "valid": all_pass,
            "errors": errors if not all_pass else [],
            "checks": checks,
        }

    validation_path = rdir / "validation.json"
    validation_path.write_text(json.dumps(result, indent=2) + "\n")

    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate a golden CSV fixture run")
    parser.add_argument("--run-dir", required=True, help="Path to the run directory")
    parser.add_argument(
        "--template-dir", default=None, help="Path to template directory"
    )
    args = parser.parse_args()

    result = validate_run(args.run_dir, args.template_dir)

    if result["valid"]:
        print("PASS")
    else:
        print("FAIL")
        for e in result.get("errors", []):
            print(f"  - {e}")
        for name, check in result.get("checks", {}).items():
            if not check.get("pass", True):
                print(f"  - {name}: failed")

    sys.exit(0 if result["valid"] else 1)


if __name__ == "__main__":
    main()
