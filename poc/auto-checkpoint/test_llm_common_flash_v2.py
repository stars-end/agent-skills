#!/usr/bin/env python3
"""POC v2: Test llm-common with GLM-4.5 FLASH for auto-commit messages.

Debug version with raw response output.
"""

import asyncio
import os
import sys
import json
from pathlib import Path

# Add llm-common to path for development
llm_common_path = Path.home() / "llm-common"
if str(llm_common_path) not in sys.path:
    sys.path.insert(0, str(llm_common_path))

from llm_common.glm_models import GLMModels
from llm_common.providers.zai_client import GLMConfig, ZaiClient


async def test_flash_model():
    """Test GLM-4.5 FLASH with various prompts."""
    api_key = os.environ.get("ZAI_API_KEY")
    if not api_key:
        raise ValueError("ZAI_API_KEY must be set in environment")

    config = GLMConfig(
        api_key=api_key,
        model=GLMModels.FLASH,
        timeout=30.0,
    )

    client = ZaiClient(config)

    print("=" * 60)
    print("POC v2: Testing GLM-4.5 FLASH responses")
    print("=" * 60)

    # Test prompts
    test_prompts = [
        "Say 'Hello, world!'",
        "Generate a git commit message for: updated docs",
        "What is 2 + 2? Answer with just the number.",
    ]

    for i, prompt in enumerate(test_prompts, 1):
        print(f"\n--- Test {i} ---")
        print(f"Prompt: {prompt}")

        try:
            response = await client.chat_completion(
                messages=[{"role": "user", "content": prompt}],
                model=GLMModels.FLASH,
                temperature=0.3,
                max_tokens=60,
            )

            print(f"Raw content: '{response.content}'")
            print(f"Content length: {len(response.content)}")
            print(f"Finish reason: {response.finish_reason}")
            print(f"Usage: {response.usage}")

            if response.metadata.get("raw_response"):
                raw = response.metadata["raw_response"]
                print(f"Raw response keys: {list(raw.keys()) if isinstance(raw, dict) else type(raw)}")

        except Exception as e:
            print(f"ERROR: {e}")
            import traceback
            traceback.print_exc()

    await client.close()
    print("\n" + "=" * 60)


async def main():
    try:
        await test_flash_model()
        return 0
    except Exception as e:
        print(f"\n❌ FAILED: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
