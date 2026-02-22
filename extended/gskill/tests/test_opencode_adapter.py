"""Tests for OpenCode adapter."""
import pytest
from extended.gskill.lib.opencode_adapter import OpenCodeAdapter, OpenCodeConfig


def test_adapter_config_defaults():
    """Test default configuration."""
    config = OpenCodeConfig()
    assert config.model == "zhipuai-coding-plan/glm-5"
    assert config.timeout == 120
    assert config.max_retries == 2


def test_adapter_is_callable():
    """Test that adapter has correct __call__ signature."""
    adapter = OpenCodeAdapter()
    assert callable(adapter)


def test_messages_to_prompt():
    """Test conversion of message list to prompt."""
    adapter = OpenCodeAdapter()

    messages = [
        {"role": "system", "content": "You are helpful."},
        {"role": "user", "content": "Hello"},
    ]

    prompt = adapter._messages_to_prompt(messages)

    assert "[SYSTEM]" in prompt
    assert "[USER]" in prompt
    assert "You are helpful." in prompt
    assert "Hello" in prompt
