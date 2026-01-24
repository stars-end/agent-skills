#!/usr/bin/env python3
"""Working POC: llm-common + GLM-4.5 FLASH (thinking disabled)."""

import asyncio
import os
import sys
from pathlib import Path

llm_common_path = Path.home() / "llm-common"
if str(llm_common_path) not in sys.path:
    sys.path.insert(0, str(llm_common_path))

from llm_common.glm_models import GLMModels
from llm_common.providers.zai_client import GLMConfig, ZaiClient


async def generate_commit_message(branch: str, diff_stat: str) -> str:
    """Generate a commit message using GLM-4.5 FLASH.

    Key: Disable thinking mode to get direct output in `content` field.
    """
    api_key = os.environ.get("ZAI_API_KEY")
    if not api_key:
        raise ValueError("ZAI_API_KEY must be set in environment")

    config = GLMConfig(
        api_key=api_key,
        model=GLMModels.FLASH,
        timeout=30.0,
    )

    client = ZaiClient(config)

    # Direct, specific prompt
    prompt = f"""Write a git commit message.

Changes: {diff_stat}

Rules:
- Start with [AUTO]
- Max 72 characters
- Use imperative mood ("add" not "added")
- No explanation, just the message

Examples: [AUTO] add docs, [AUTO] fix auth bug

Message:"""

    try:
        # CRITICAL: Disable thinking for glm-4.5 to get direct content
        response = await client.chat_completion(
            messages=[{"role": "user", "content": prompt}],
            model=GLMModels.FLASH,
            temperature=0.3,
            max_tokens=80,
            extra_body={"thinking": {"type": "disabled"}},
        )

        await client.close()

        # Extract just the message line
        message = response.content.strip()

        # Take only the first line if model added extras
        if "\n" in message:
            message = message.split("\n")[0].strip()

        # Remove any markdown formatting
        for marker in ["**", "*", "`", '"', "'"]:
            message = message.replace(marker, "")

        message = message.strip()

        # Ensure [AUTO] prefix
        if not message.startswith("[AUTO]"):
            message = f"[AUTO] {message}"

        # Truncate if needed
        if len(message) > 72:
            message = message[:69] + "..."

        return message

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise


async def main():
    """Run the working POC."""
    print("=" * 70)
    print("WORKING POC: llm-common + GLM-4.5 FLASH (thinking disabled)")
    print("=" * 70)

    test_cases = [
        ("feature-auto-checkpoint-poc", "docs/REPO_SYNC_STRATEGY.md | 1 +"),
        ("feature-auth", "src/auth.py | 5 +2"),
        ("fix-bug-123", "README.md | 10 +++"),
        ("wip", "pkg/new_feature | 100 +"),
    ]

    print(f"\nConfiguration:")
    print(f"  Library: llm-common")
    print(f"  Model: {GLMModels.FLASH}")
    print(f"  Thinking: DISABLED (via extra_body)")

    print(f"\nRunning {len(test_cases)} test cases...")
    print("-" * 70)

    for i, (branch, diff_stat) in enumerate(test_cases, 1):
        print(f"\nTest {i}/{len(test_cases)}")
        print(f"  Input: {diff_stat}")

        try:
            message = await generate_commit_message(branch, diff_stat)
            valid = "✅" if (message.startswith("[AUTO]") and len(message) <= 72) else "⚠️"
            print(f"  {valid} {message} ({len(message)} chars)")

        except Exception as e:
            print(f"  ❌ {e}")

    print("\n" + "=" * 70)
    print("✅ POC COMPLETE!")
    print("\nKey findings:")
    print("  1. Use GLMModels.FLASH (glm-4.5) for cheap/fast generation")
    print("  2. Disable thinking: extra_body={'thinking': {'type': 'disabled'}}")
    print("  3. Use direct prompts to avoid verbose responses")
    print("=" * 70)

    return 0


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
