"""
OpenCode LanguageModel Adapter for GEPA.

Wraps opencode CLI to implement GEPA's LanguageModel protocol.
"""

import subprocess
from typing import Union
from dataclasses import dataclass


@dataclass
class OpenCodeConfig:
    """Configuration for OpenCode adapter."""
    model: str = "zhipuai-coding-plan/glm-5"
    timeout: int = 120  # seconds
    max_retries: int = 2
    format: str = "default"  # "default" or "json"
    workdir: str | None = None


class OpenCodeAdapter:
    """
    GEPA LanguageModel protocol implementation using opencode.

    Implements: __call__(prompt: str | list[dict]) -> str
    """

    def __init__(self, config: OpenCodeConfig = None):
        self.config = config or OpenCodeConfig()

    def __call__(self, prompt: Union[str, list[dict]]) -> str:
        """
        Call opencode with prompt, return response.

        Args:
            prompt: String or list of message dicts (OpenAI format)

        Returns:
            Model response as string
        """
        if isinstance(prompt, list):
            prompt = self._messages_to_prompt(prompt)

        for attempt in range(self.config.max_retries + 1):
            try:
                # Build command - message is POSITIONAL, not -p
                cmd = [
                    "opencode", "run",
                    "-m", self.config.model,
                    "--format", self.config.format,
                    prompt  # Positional message
                ]
                if self.config.workdir:
                    cmd.extend(["--dir", self.config.workdir])

                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    timeout=self.config.timeout
                )
                if result.returncode == 0:
                    return result.stdout.strip()
                else:
                    raise RuntimeError(f"opencode failed: {result.stderr}")
            except subprocess.TimeoutExpired:
                if attempt == self.config.max_retries:
                    raise RuntimeError(f"opencode timed out after {self.config.timeout}s")
                continue
            except Exception as e:
                if attempt == self.config.max_retries:
                    raise
                continue

        raise RuntimeError("opencode failed after retries")

    def _messages_to_prompt(self, messages: list[dict]) -> str:
        """Convert OpenAI-style messages to single prompt."""
        parts = []
        for msg in messages:
            role = msg.get("role", "user")
            content = msg.get("content", "")
            parts.append(f"[{role.upper()}]\n{content}")
        return "\n\n".join(parts)


def make_opencode_lm(model: str = "zhipuai-coding-plan/glm-5") -> callable:
    """Factory function for GEPA compatibility."""
    return OpenCodeAdapter(OpenCodeConfig(model=model))
