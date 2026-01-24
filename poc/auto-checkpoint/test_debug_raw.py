#!/usr/bin/env python3
"""Debug raw response from GLM-4.5 FLASH."""

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

    print(f"Prompt: {repr(prompt)}")

    response = await client.chat_completion(
        messages=[{"role": "user", "content": prompt}],
        max_tokens=100,
    )

    print(f"\nResponse:")
    print(f"  content: '{response.content}'")
    print(f"  repr: {repr(response.content)}")
    print(f"  length: {len(response.content)}")
    print(f"  finish_reason: {response.finish_reason}")

    # Check raw response
    if response.metadata.get("raw_response"):
        raw = response.metadata["raw_response"]
        print(f"\nRaw response:")
        print(json.dumps(raw, indent=2))

    await client.close()
    return 0


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
