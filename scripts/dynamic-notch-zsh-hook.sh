#!/usr/bin/env zsh
# ==============================================================================
# Dynamic Notch - Automatic Zsh Shell Hook for Long-Running Commands
# ==============================================================================
# When a terminal command runs longer than NOTCH_THRESHOLD_SECONDS (default: 3s),
# Dynamic Notch automatically displays a live activity spinner and elapsed timer.
# When the command finishes, it triggers a success (green) or failure (red) alert.
# ==============================================================================

NOTCH_THRESHOLD_SECONDS=${NOTCH_THRESHOLD_SECONDS:-3}

__notch_preexec() {
    local NOTCH_BIN="${DYNAMIC_NOTCH_BIN:-$HOME/.local/bin/notch}"
    [[ -x "$NOTCH_BIN" ]] || return
    
    local full_cmd="$1"
    local first_word="${full_cmd%% *}"
    first_word="${first_word##*/}"
    
    # Exclude interactive programs, editors, pagers, REPLs, and notch commands
    case "$first_word" in
        vim|nvim|vi|nano|emacs|less|more|man|top|htop|btop|ssh|notch|dynamic-notch|python|python3|node|irb|gh|tig|git-log|source|\.)
            return
            ;;
    esac
    
    [[ -z "$full_cmd" ]] && return
    
    local clean_title="${full_cmd//\"/}"
    clean_title="${clean_title//\'/}"
    if [[ ${#clean_title} -gt 50 ]]; then
        clean_title="${clean_title:0:47}..."
    fi
    
    __NOTCH_CMD_TITLE="$clean_title"
    __NOTCH_CMD_START_TIME=$SECONDS
    
    local pending_file="/tmp/notch_pending_$$"
    local active_file="/tmp/notch_active_$$"
    
    rm -f "$active_file"
    touch "$pending_file"
    
    # Spawn detached delay-start watcher in background without job table notifications
    "$NOTCH_BIN" activity delay-start "zsh_$$" "${NOTCH_THRESHOLD_SECONDS:-3}" "$pending_file" "$active_file" "$clean_title" >/dev/null 2>&1 &!
}

__notch_precmd() {
    local exit_code=$?
    local NOTCH_BIN="${DYNAMIC_NOTCH_BIN:-$HOME/.local/bin/notch}"
    local pending_file="/tmp/notch_pending_$$"
    local active_file="/tmp/notch_active_$$"
    
    # Clear pending trigger immediately so watcher aborts if it hasn't fired yet
    rm -f "$pending_file"
    
    local elapsed=$(( SECONDS - __NOTCH_CMD_START_TIME ))
    
    # If the activity was activated or command ran >= threshold
    if [[ -f "$active_file" || $elapsed -ge ${NOTCH_THRESHOLD_SECONDS:-3} ]]; then
        rm -f "$active_file"
        
        local mins=$(( elapsed / 60 ))
        local secs=$(( elapsed % 60 ))
        local elapsed_formatted
        if [[ $mins -gt 0 ]]; then
            elapsed_formatted="${mins}m ${secs}s"
        else
            elapsed_formatted="${secs}s"
        fi
        
        if [[ $exit_code -eq 0 ]]; then
            "$NOTCH_BIN" activity complete "zsh_$$" "Completed: $__NOTCH_CMD_TITLE" "Finished in ${elapsed_formatted}" >/dev/null 2>&1
        else
            "$NOTCH_BIN" activity fail "zsh_$$" "Exited with code $exit_code" >/dev/null 2>&1
        fi
    fi
}

# Register zsh hook functions using add-zsh-hook
autoload -Uz add-zsh-hook
add-zsh-hook preexec __notch_preexec
add-zsh-hook precmd __notch_precmd
