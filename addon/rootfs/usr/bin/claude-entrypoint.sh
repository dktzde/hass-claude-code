#!/usr/bin/env bash
# ==============================================================================
# Claude Code Add-on: Claude entrypoint
# Launches Claude Code with flags based on add-on configuration.
# This runs inside tmux, spawned by ttyd.
# ==============================================================================
set -e

# Source environment (written by init-claude)
if [[ -f /etc/profile.d/claude.sh ]]; then
    # shellcheck source=/dev/null
    source /etc/profile.d/claude.sh
fi

# Build claude args
declare -a CLAUDE_ARGS=()

# Model selection
if [[ -n "${CLAUDE_MODEL:-}" && "${CLAUDE_MODEL}" != "default" ]]; then
    CLAUDE_ARGS+=(--model "${CLAUDE_MODEL}")
fi

# Yolo mode is handled via managed-settings.json (permissions.allow all tools)
# instead of --dangerously-skip-permissions which is blocked when running as root.

echo "Starting Claude Code..."
echo "Working directory: $(pwd)"
echo ""

# Launch Claude Code
exec claude "${CLAUDE_ARGS[@]}"
