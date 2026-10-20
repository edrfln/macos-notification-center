#!/usr/bin/env bash
# ==============================================================================
# Dynamic Notch - Claude Code Hook Bridge
# ==============================================================================
# Mirrors Claude Code session activity into the notch. Wire it into
# ~/.claude/settings.json hooks, passing the hook event name as the only argument:
#
#   UserPromptSubmit -> live activity "Claude · <project>" (after a short delay,
#                       so quick answers never flash the pill)
#   PreToolUse       -> activity subtitle: "Editing Foo.swift", "Running tests"...
#   Notification     -> alert when Claude needs permission or input
#   Stop             -> completes the activity with a "finished" alert
#   SessionEnd       -> closes a still-running activity (only if you exit mid-turn)
#
# Reads the hook JSON from stdin. Always exits 0 so it can never block Claude.
# ==============================================================================

NOTCH_BIN="${DYNAMIC_NOTCH_BIN:-$HOME/.local/bin/notch}"
NOTCH_DELAY_SECONDS="${NOTCH_CLAUDE_DELAY_SECONDS:-4}"
STATE_DIR="${TMPDIR:-/tmp}/claude-notch"

event="$1"
input="$(cat)"

[[ -x "$NOTCH_BIN" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
mkdir -p "$STATE_DIR"

field() {
    jq -r "$1 // empty" <<<"$input" 2>/dev/null
}

truncate_label() {
    local text="$1" max="${2:-42}"
    text="${text//$'\n'/ }"
    if (( ${#text} > max )); then
        text="${text:0:max-1}…"
    fi
    printf '%s' "$text"
}

session_id="$(field '.session_id')"
[[ -n "$session_id" ]] || exit 0
activity_id="claude_${session_id:0:8}"
project="$(basename "$(field '.cwd')")"
[[ -n "$project" && "$project" != "." ]] || project="session"

pending_file="$STATE_DIR/${activity_id}.pending"
active_file="$STATE_DIR/${activity_id}.active"

# Human-readable label for the tool Claude is about to use.
tool_label() {
    local tool path
    tool="$(field '.tool_name')"
    case "$tool" in
        Edit|MultiEdit|Write|NotebookEdit)
            path="$(field '.tool_input.file_path // .tool_input.notebook_path')"
            echo "Editing $(basename "${path:-file}")" ;;
        Read)
            path="$(field '.tool_input.file_path')"
            echo "Reading $(basename "${path:-file}")" ;;
        Bash)
            local desc
            desc="$(field '.tool_input.description')"
            [[ -n "$desc" ]] || desc="$(field '.tool_input.command')"
            truncate_label "Running: $desc" ;;
        Grep|Glob)
            echo "Searching the codebase" ;;
        Task|Agent)
            truncate_label "Delegating: $(field '.tool_input.description')" ;;
        WebFetch|WebSearch)
            echo "Browsing the web" ;;
        TodoWrite)
            echo "Planning next steps" ;;
        mcp__*)
            local server="${tool#mcp__}"
            echo "Using ${server%%__*}" ;;
        "")
            echo "Working…" ;;
        *)
            echo "Using $tool" ;;
    esac
}

case "$event" in
    UserPromptSubmit)
        rm -f "$active_file"
        touch "$pending_file"
        # Detached watcher: only shows the pill if Claude is still working after the delay.
        nohup "$NOTCH_BIN" activity delay-start "$activity_id" "$NOTCH_DELAY_SECONDS" \
            "$pending_file" "$active_file" "Claude · $project" "Thinking…" "sparkles" \
            >/dev/null 2>&1 &
        disown 2>/dev/null
        ;;

    PreToolUse)
        if [[ -f "$active_file" ]]; then
            "$NOTCH_BIN" activity update "$activity_id" "$(tool_label)" >/dev/null 2>&1
        fi
        ;;

    Notification)
        message="$(field '.message')"
        kind="$(field '.notification_type')"
        # Skip the "waiting for your input" idle reminder; Stop already announced the finish.
        if [[ "$kind" == "idle_prompt" || "$message" == *"waiting for your input"* ]]; then
            exit 0
        fi
        "$NOTCH_BIN" alert "Claude needs you · $project" \
            "$(truncate_label "${message:-Waiting for your response}" 70)" \
            "Claude Code" "reminder" >/dev/null 2>&1
        ;;

    Stop)
        rm -f "$pending_file"
        if [[ -f "$active_file" ]]; then
            rm -f "$active_file"
            "$NOTCH_BIN" activity complete "$activity_id" \
                "Claude finished · $project" "Ready for your next prompt" >/dev/null 2>&1
        fi
        ;;

    SessionEnd)
        rm -f "$pending_file"
        if [[ -f "$active_file" ]]; then
            rm -f "$active_file"
            "$NOTCH_BIN" activity fail "$activity_id" "Session ended" >/dev/null 2>&1
        fi
        ;;
esac

exit 0
