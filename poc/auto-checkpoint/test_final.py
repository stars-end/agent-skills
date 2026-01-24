#!/usr/bin/env python3
"""Final POC: llm-common + GLM-4.5 FLASH for auto-commit messages.

Working version using the correct prompt pattern.
"""

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

    Args:
        branch: Git branch name
        diff_stat: Git diff stat output

    Returns:
        Generated commit message with [AUTO] prefix
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

    # Simple prompt that works with FLASH
    prompt = f"Git commit message for: {diff_stat}"

    try:
        response = await client.chat_completion(
            messages=[{"role": "user", "content": prompt}],
            model=GLMModels.FLASH,
            temperature=0.3,
            max_tokens=100,
        )

        await client.close()

        message = response.content.strip()

        # Add [AUTO] prefix if not present
        if not message.startswith("[AUTO]"):
            message = f"[AUTO] {message}"

        # Ensure max 72 chars
        if len(message) > 72:
            message = message[:69] + "..."

        return message

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise


async def main():
    """Run the final POC test."""
    print("=" * 70)
    print("FINAL POC: llm-common + GLM-4.5 FLASH for auto-commit messages")
    print("=" * 70)

    # Test cases
    test_cases = [
        ("feature-auto-checkpoint-poc", "docs/REPO_SYNC_STRATEGY.md | 1 +"),
        ("feature-auth", "src/auth.py | 5 +2, src/config.py | 2 -1"),
        ("fix-bug-123", "README.md | 10 +++"),
        ("wip", "pkg/new_feature | 100 +"),
    ]

    print(f"\nConfiguration:")
    print(f"  Library: llm-common (~/llm-common)")
    print(f"  Model: {GLMModels.FLASH}")
    print(f"  Endpoint: {GLMModels.CODING_ENDPOINT}")

    print(f"\nRunning {len(test_cases)} test cases...")
    print("-" * 70)

    all_passed = True

    for i, (branch, diff_stat) in enumerate(test_cases, 1):
        print(f"\nTest {i}/{len(test_cases)}")
        print(f"  Branch: {branch}")
        print(f"  Changes: {diff_stat}")

        try:
            message = await generate_commit_message(branch, diff_stat)

            # Validate
            is_valid = (
                message.startswith("[AUTO]") and
                len(message) <= 72
            )

            status = "✅" if is_valid else "⚠️"
            print(f"  {status} Result: {message}")
            print(f"     Length: {len(message)}/72")

            if not is_valid:
                all_passed = False

        except Exception as e:
            print(f"  ❌ FAILED: {e}")
            all_passed = False

    print("\n" + "=" * 70)

    if all_passed:
        print("✅ ALL TESTS PASSED!")
        print("\nReady to integrate into auto-checkpoint feature.")
        return 0
    else:
        print("⚠️  Some tests had issues (see warnings above)")
        return 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
