#!/usr/bin/env bash
# setup-kilocode-skills.sh - Symlink agent-skills to Kilo Code
#
# Usage: ./setup-kilocode-skills.sh
#
# This script creates symlinks from ~/.kilocode/skills-* to ~/agent-skills/*
# enabling Kilo Code to use all agent-skills capabilities.

set -e

KILOCODE_DIR="$HOME/.kilocode"
AGENT_SKILLS_DIR="$HOME/agent-skills"

# Categories to symlink to generic skills (all modes)
CATEGORIES="core extended health infra dispatch search safety"

echo "🔗 Setting up Kilo Code skills symlinks..."
echo "   From: $AGENT_SKILLS_DIR"
echo "   To:   $KILOCODE_DIR"
echo

# Create .kilocode directory if it doesn't exist
if [ ! -d "$KILOCODE_DIR" ]; then
    echo "Creating $KILOCODE_DIR..."
    mkdir -p "$KILOCODE_DIR"
fi

# Remove existing symlinks if they exist (force refresh)
for category in $CATEGORIES; do
    link_path="$KILOCODE_DIR/skills-$category"
    if [ -L "$link_path" ]; then
        echo "Removing existing symlink: $link_path"
        rm "$link_path"
    fi
done

# Create symlinks
for category in $CATEGORIES; do
    source_path="$AGENT_SKILLS_DIR/$category"
    link_path="$KILOCODE_DIR/skills-$category"

    if [ ! -d "$source_path" ]; then
        echo "⚠️  Warning: $source_path does not exist, skipping..."
        continue
    fi

    echo "Linking: skills-$category -> $source_path"
    ln -s "$source_path" "$link_path"
done

echo
echo "✅ Done! Kilo Code now has access to all agent-skills."
echo
echo "Symlinks created:"
ls -la "$KILOCODE_DIR"/skills-* 2>/dev/null || echo "None (check agent-skills directory)"
