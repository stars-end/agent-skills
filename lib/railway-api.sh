#!/bin/bash
# railway-api.sh - Railway GraphQL API wrapper
#
# Part of the agent-skills registry
# Compatible with: Claude Code, Codex CLI, OpenCode, Gemini CLI, Antigravity
#
# Usage:
#   railway-api.sh 'query { currentUser { id } }' '{}'
#
# Environment variables:
#   RAILWAY_TOKEN - Railway API token (defaults to railway config)
#   RAILWAY_API_ENDPOINT - GraphQL endpoint (defaults to https://backboard.railway.com/graphql/v2)

set -euo pipefail

# GraphQL endpoint
RAILWAY_API_ENDPOINT="${RAILWAY_API_ENDPOINT:-https://backboard.railway.com/graphql/v2}"

# Get Railway token from config or environment
get_railway_token() {
    if [[ -n "${RAILWAY_TOKEN:-}" ]]; then
        echo "$RAILWAY_TOKEN"
        return
    fi

    # Try to get token from railway config
    if command -v railway &>/dev/null; then
        # Railway stores token in ~/.config/railway/config.json
        local config_file="$HOME/.config/railway/config.json"
        if [[ -f "$config_file" ]]; then
            if command -v jq &>/dev/null; then
                jq -r '.token // empty' "$config_file" 2>/dev/null || echo ""
            else
                grep -o '"token":"[^"]*"' "$config_file" 2>/dev/null | cut -d'"' -f4 || echo ""
            fi
        fi
    fi
}

# Execute GraphQL query/mutation
railway_graphql() {
    local query="$1"
    local variables="${2:-{}}"

    local token
    token=$(get_railway_token)

    if [[ -z "$token" ]]; then
        echo "Error: Railway token not found. Run 'railway login'" >&2
        return 1
    fi

    local response
    response=$(curl -s \
        -X POST \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{\"query\":$(echo "$query" | jq -Rs .), \"variables\":$(echo "$variables" | jq -c .)}" \
        "$RAILWAY_API_ENDPOINT")

    # Check for errors
    if echo "$response" | jq -e '.errors' &>/dev/null; then
        echo "GraphQL errors:" >&2
        echo "$response" | jq -r '.errors[] | "  \(.message)"' >&2
        return 1
    fi

    echo "$response"
}

# Main function
railway_api() {
    local query="$1"
    local variables="${2:-{}}"

    # Validate inputs
    if [[ -z "$query" ]]; then
        echo "Usage: railway-api.sh 'query { ... }' '{variables}'" >&2
        return 1
    fi

    # Execute query
    railway_graphql "$query" "$variables"
}

# Export functions
export -f get_railway_token
export -f railway_graphql
export -f railway_api

# If script is executed directly (not sourced), run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    railway_api "$@"
fi
