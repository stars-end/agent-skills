# Slack MCP Server Setup Guide

## Quick Start (5 minutes)

### Step 1: Create Slack App

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Click **Create New App** → **From manifest**
3. Paste this manifest:

```json
{
    "display_information": {
        "name": "Agent Coordination"
    },
    "oauth_config": {
        "scopes": {
            "user": [
                "channels:history",
                "channels:read",
                "groups:history",
                "groups:read",
                "im:history",
                "im:read",
                "im:write",
                "mpim:history",
                "mpim:read",
                "mpim:write",
                "users:read",
                "chat:write",
                "search:read"
            ]
        }
    },
    "settings": {
        "org_deploy_enabled": false,
        "socket_mode_enabled": false,
        "token_rotation_enabled": false
    }
}
```

4. Click **Create** and select your workspace
5. Go to **OAuth & Permissions** → **Install to [Workspace]**
6. Copy the **User OAuth Token** (starts with `xoxp-`)

### Step 2: Create Channel

1. In Slack, create channel `#affordabot-agents`
2. Add yourself to the channel

### Step 3: Set Environment Variable

```bash
# Add to ~/.bashrc or ~/.zshrc
export SLACK_MCP_XOXP_TOKEN="xoxp-your-token-here"
```

### Step 4: Test the Server

```bash
# Reload shell
source ~/.zshrc

# Test - should start without error
slack-mcp-server -t stdio
# Press Ctrl+C to stop
```

## Antigravity Configuration

Once you have the token, the Slack MCP server will be available in Antigravity.
The server provides these tools:

- `conversations_history` - Fetch messages from a channel
- `conversations_add_message` - Send a message
- `conversations_replies` - Get thread replies
- `conversations_search_messages` - Search messages
- `channels_list` - List available channels

## Usage Examples

**Check inbox:**
```
Use conversations_history to check #affordabot-agents for new messages
```

**Send message:**
```
Use conversations_add_message to post "Task bd-xxx complete" to #affordabot-agents
```

**Reply in thread:**
```
Use conversations_replies to reply to specific message thread
```
