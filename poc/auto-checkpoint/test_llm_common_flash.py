#!/usr/bin/env python3
"""POC: Test llm-common with GLM-4.5 FLASH for auto-commit messages.

This demonstrates the pattern for generating commit messages using:
- llm-common library (~/llm-common)
- GLMModels.FLASH (glm-4.5) - cheap/fast model
- ZaiClient with OpenAI-compatible API

Usage:
    cd ~/llm-common && poetry run python ../agent-skills/poc/auto-checkpoint/test_llm_common_flash.py
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

    # Configure client with FLASH model (cheap/fast)
    config = GLMConfig(
        api_key=api_key,
        model=GLMModels.FLASH,  # glm-4.5
        timeout=30.0,
    )

    client = ZaiClient(config)

    prompt = f"""Generate a one-line git commit message (max 72 chars) for this auto-checkpoint.

Branch: {branch}
Changes: {diff_stat}

Requirements:
- Start with [AUTO] prefix
- Be concise
- Focus on WHAT changed, not WHY
- Example: [AUTO] checkpoint: update auth, add logging

Output ONLY the commit message, nothing else."""

    try:
        response = await client.chat_completion(
            messages=[{"role": "user", "content": prompt}],
            model=GLMModels.FLASH,
            temperature=0.3,
            max_tokens=60,
        )

        await client.close()

        # Clean up response
        message = response.content.strip()
        # Remove quotes if LLM wrapped it
        message = message.strip('"').strip("'")

        return message

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise


async def main():
    """Run the POC test."""
    print("=" * 60)
    print("POC: llm-common + GLM-4.5 FLASH for auto-commit messages")
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

        # Validate format
        if not message.startswith("[AUTO]"):
            print(f"\n⚠️  Warning: Message doesn't start with [AUTO] prefix")

        if len(message) > 72:
            print(f"\n⚠️  Warning: Message exceeds 72 chars (len={len(message)})")

        print(f"\nLength: {len(message)}/72 chars")
        print("\n" + "=" * 60)

        return 0

    except Exception as e:
        print(f"\n❌ FAILED: {e}")
        return 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
