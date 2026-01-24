#!/usr/bin/env python3
"""POC v3: Test llm-common with GLM-4.5 FLASH for auto-commit messages.

Fixed version with proper max_tokens and prompts.
"""

import asyncio
import os
import sys
from pathlib import Path

# Add llm-common to path for development
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
        Generated commit message
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

    # Simpler, more direct prompt
    prompt = f"""Write a git commit message.

Branch: {branch}
Changes: {diff_stat}

Format: [AUTO] <brief description>
Max 72 characters.

Examples:
[AUTO] update auth config
[AUTO] fix rate limit handling
[AUTO] add logging middleware

Commit message:"""

    try:
        response = await client.chat_completion(
            messages=[{"role": "user", "content": prompt}],
            model=GLMModels.FLASH,
            temperature=0.3,
            max_tokens=100,  # Increased from 60
        )

        await client.close()

        # Clean up response
        message = response.content.strip()

        # Remove common prefixes the model might add
        for prefix in ["Commit message: ", "Message: ", '"', "'"]:
            if message.startswith(prefix):
                message = message[len(prefix):]

        message = message.strip()

        # Truncate if too long
        if len(message) > 72:
            message = message[:69] + "..."

        return message

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise


async def main():
    """Run the POC test."""
    print("=" * 60)
    print("POC v3: llm-common + GLM-4.5 FLASH")
    print("=" * 60)

    # Test data
    branch = "feature-auto-checkpoint-poc"
    diff_stat = "docs/REPO_SYNC_STRATEGY.md | 1 +"

    print(f"\nInput:")
    print(f"  Branch: {branch}")
    print(f"  Changes: {diff_stat}")
    print(f"  Model: {GLMModels.FLASH}")

    print("\nGenerating commit message...")

    try:
        message = await generate_commit_message(branch, diff_stat)

        print(f"\n✅ SUCCESS!")
        print(f"\nGenerated message:")
        print(f"  {message}")

        print(f"\nLength: {len(message)}/72 chars")

        # Run multiple tests to show consistency
        print("\n" + "-" * 40)
        print("Running 3 more tests for consistency...")

        for i in range(1, 4):
            msg = await generate_commit_message(branch, diff_stat)
            print(f"  Test {i}: {msg}")

        print("\n" + "=" * 60)

        return 0

    except Exception as e:
        print(f"\n❌ FAILED: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
