#!/usr/bin/env python3
"""Test glm-4.5 with thinking disabled."""

import asyncio
import os
import sys
import json
from pathlib import Path

llm_common_path = Path.home() / "llm-common"
if str(llm_common_path) not in sys.path:
    sys.path.insert(0, str(llm_common_path))

from llm_common.glm_models import GLMModels
from llm_common.providers.zai_client import GLMConfig, ZaiClient


async def main():
    api_key = os.environ.get("ZAI_API_KEY")
    config = GLMConfig(api_key=api_key, model=GLMModels.FLASH)
    client = ZaiClient(config)

    prompt = "Git commit message for: docs/REPO_SYNC_STRATEGY.md | 1 +"

    print("=" * 60)
    print("Test: glm-4.5 with thinking DISABLED")
    print("=" * 60)
    print(f"Prompt: {repr(prompt)}")

    # Try with thinking disabled
    response = await client.chat_completion(
        messages=[{"role": "user", "content": prompt}],
        max_tokens=100,
        extra_body={"thinking": {"type": "disabled"}},
    )

    print(f"\nWith thinking disabled:")
    print(f"  content: '{response.content}'")
    print(f"  length: {len(response.content)}")

    # Also check raw response
    if response.metadata.get("raw_response"):
        raw = response.metadata["raw_response"]
        msg = raw["choices"][0]["message"]
        print(f"  raw content: {repr(msg.get('content'))}")
        print(f"  raw reasoning: {repr(msg.get('reasoning_content', '')[:50])}")

    await client.close()

    # Try WITHOUT extra_body (default behavior)
    print("\n" + "-" * 60)
    print("Test: glm-4.5 WITHOUT extra_body (default)")
    print("-" * 60)

    client2 = ZaiClient(config)
    response2 = await client2.chat_completion(
        messages=[{"role": "user", "content": prompt}],
        max_tokens=100,
    )

    print(f"\nDefault behavior:")
    print(f"  content: '{response2.content}'")

    if response2.metadata.get("raw_response"):
        raw = response2.metadata["raw_response"]
        msg = raw["choices"][0]["message"]
        print(f"  raw reasoning: {repr(msg.get('reasoning_content', '')[:80])}")

    await client2.close()

    return 0


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
