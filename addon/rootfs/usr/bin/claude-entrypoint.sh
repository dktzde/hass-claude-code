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

# The model, API URL and token come from the ANTHROPIC_* variables of
# claude.sh (add-on options anthropic_*), which Claude Code reads itself.

echo "Starting Claude Code..."
echo "Working directory: $(pwd)"
echo ""

# Option mobile_tabs: the second line of the tab bar shows the model and the
# effort of each tab. Claude Code passes both only to its status line command,
# so tmux-tab-info is set as the status line for this session. Only if the
# user has no status line of their own: settings passed with --settings win
# over the user's and project settings.
declare -a claude_args=()
if [[ -n "${TMUX:-}" ]] &&
   [[ "$(tmux show -gqv @hcc_tab_info 2> /dev/null)" == "on" ]]; then
    own_status_line=false
    for file in "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/settings.json" \
        "${PWD}/.claude/settings.json" "${PWD}/.claude/settings.local.json"; do
        if [[ -f "${file}" ]] &&
           jq -e '.statusLine != null' "${file}" > /dev/null 2>&1; then
            own_status_line=true
        fi
    done
    if [[ "${own_status_line}" == false ]]; then
        claude_args+=(--settings
            '{"statusLine":{"type":"command","command":"/usr/bin/tmux-tab-info"}}')
    fi
fi

# Launch Claude Code
exec claude "${claude_args[@]}"
