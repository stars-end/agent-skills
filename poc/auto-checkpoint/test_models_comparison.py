#!/usr/bin/env python3
"""Compare GLM models for commit message generation."""

import asyncio
import os
import sys
from pathlib import Path

llm_common_path = Path.home() / "llm-common"
if str(llm_common_path) not in sys.path:
    sys.path.insert(0, str(llm_common_path))

from llm_common.glm_models import GLMModels
from llm_common.providers.zai_client import GLMConfig, ZaiClient


async def test_model(model_name: str, model_value: str):
    """Test a specific model."""
    api_key = os.environ.get("ZAI_API_KEY")
    if not api_key:
        raise ValueError("ZAI_API_KEY must be set in environment")

    config = GLMConfig(api_key=api_key, model=model_value, timeout=30.0)
    client = ZaiClient(config)

    prompt = "Write a git commit message for: updated docs\n\nJust the message, no explanation."

    print(f"\n{'=' * 50}")
    print(f"Model: {model_name} ({model_value})")
    print(f"{'=' * 50}")
    print(f"Prompt: {repr(prompt)}")

    try:
        response = await client.chat_completion(
            messages=[{"role": "user", "content": prompt}],
            model=model_value,
            temperature=0.3,
            max_tokens=100,
        )

        print(f"Content: '{response.content}'")
        print(f"Length: {len(response.content)}")
        print(f"Finish reason: {response.finish_reason}")
        print(f"Tokens: {response.usage}")

        if not response.content:
            print("⚠️  EMPTY RESPONSE!")

            # Try without the "Just the message" constraint
            print("\nRetrying with simpler prompt...")
            response2 = await client.chat_completion(
                messages=[{"role": "user", "content": "Git commit for: updated docs"}],
                model=model_value,
                max_tokens=100,
            )
            print(f"Retry content: '{response2.content}'")
            print(f"Retry finish: {response2.finish_reason}")

    except Exception as e:
        print(f"ERROR: {e}")

    await client.close()


async def main():
    """Test all models."""
    print("=" * 60)
    print("Comparing GLM models for commit message generation")
    print("=" * 60)

    models_to_test = [
        ("FLASH", GLMModels.FLASH),
        ("FLAGSHIP", GLMModels.FLAGSHIP),
    ]

    for name, value in models_to_test:
        await test_model(name, value)

    return 0


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
