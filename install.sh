#!/bin/bash

# Claude Toolkit Installer
# Copies .claude/ directory to target project

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-.}"

# Resolve target to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

if [ ! -d "$SCRIPT_DIR/.claude" ]; then
    echo "Error: .claude directory not found in toolkit"
    exit 1
fi

if [ -d "$TARGET_DIR/.claude" ]; then
    echo "Warning: $TARGET_DIR/.claude already exists"
    read -p "Overwrite? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 1
    fi
    rm -rf "$TARGET_DIR/.claude"
fi

echo "Installing Claude toolkit to: $TARGET_DIR"

# Copy .claude directory
cp -r "$SCRIPT_DIR/.claude" "$TARGET_DIR/.claude"

# Make hooks executable
chmod +x "$TARGET_DIR/.claude/hooks/"*.sh 2>/dev/null || true

# Set sync version for future updates
if [ -f "$SCRIPT_DIR/VERSION" ]; then
    cp "$SCRIPT_DIR/VERSION" "$TARGET_DIR/.claude-sync-version"
fi

echo ""
echo "Installed successfully!"
echo ""
echo "Next steps:"
echo "  1. Review .claude/settings.local.json and adjust permissions"
echo "  2. Customize .claude/memories/ for your project"
echo "  3. Remove Python-specific hooks if not using Python:"
echo "     - .claude/hooks/enforce-uv-run.sh"
echo ""
echo "For future updates, use: claude-toolkit sync $TARGET_DIR"
echo ""
