#!/usr/bin/env python3
import argparse
from typing import Optional


def build_prompt(beads: str, interval: int, provider: str, target: str, pr: Optional[str]) -> str:
    interval_minutes = max(1, interval // 60)
    lines = [
        f"Start a governed {provider} wave for `{beads}` if one is not already active.",
        f"Then enter a recurring control cycle with a {interval}-second sleep interval ({interval_minutes}m).",
        "",
        f"Target: {target}",
        f"Beads item: {beads}",
        "",
        "Cycle:",
        f"1. Sleep {interval} seconds.",
        f"2. Check `dx-runner check --beads {beads} --json`.",
        f"3. If the state is still healthy and there is no material change, stay quiet.",
        f"4. If deeper outcome detail is needed, inspect `dx-runner report --beads {beads} --format json`.",
        "5. If the wave is blocked, exited without the expected artifact, or needs a human decision, interrupt with current state, what changed, and the exact next action.",
        "6. If the failure is deterministic and bounded, prepare a one-shot re-dispatch prompt for the next round.",
        "7. If the failure is semantic or ambiguous, do not invent a retry; surface a decision request instead.",
    ]
    if pr:
        lines.extend(
            [
                "",
                f"PR transition: once PR #{pr} exists, also watch its checks.",
                f"- Stay quiet while checks are pending and unchanged.",
                "- Interrupt on failed checks, requested changes, or merge-ready state.",
            ]
        )
    lines.extend(
        [
            "",
            "Interrupt conditions:",
            "- merge_ready",
            "- blocked",
            "- needs_decision",
            "",
            "Boundaries:",
            "- Do not expand scope.",
            "- Do not auto-merge.",
            "- Do not create new work items unless explicitly instructed.",
        ]
    )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Render a Codex-first loop orchestration prompt.")
    parser.add_argument("--beads", required=True, help="Beads issue id to monitor.")
    parser.add_argument("--interval", type=int, default=600, help="Sleep interval in seconds.")
    parser.add_argument("--provider", default="opencode", help="dx-runner provider name.")
    parser.add_argument("--target", required=True, help="Human-readable target description.")
    parser.add_argument("--pr", help="Optional PR number for post-dispatch babysitting.")
    args = parser.parse_args()
    print(build_prompt(args.beads, args.interval, args.provider, args.target, args.pr))


if __name__ == "__main__":
    main()
