#!/usr/bin/env fish

# Core utility functions for the forge fish plugin

# Lazily loads and caches `forge list commands --porcelain`, avoiding the
# startup cost of running forge when the plugin is sourced.
function __forge_get_commands --description 'Print the cached forge command catalogue'
    if test -z "$_FORGE_COMMANDS"
        set -g _FORGE_COMMANDS (CLICOLOR_FORCE=0 command $_FORGE_BIN list commands --porcelain 2>/dev/null | string collect)
    end
    printf '%s\n' $_FORGE_COMMANDS
end

# Prints NUL-separated KEY=VALUE pairs carrying the session overrides and the
# terminal-context ring buffer for a child forge process. Callers splice the
# result into `env` so nothing leaks into the shell session:
#     env (__forge_session_env | string split0) forge …
function __forge_session_env --description 'Print environment overrides for a child forge process'
    test -n "$_FORGE_SESSION_MODEL"; and printf 'FORGE_SESSION__MODEL_ID=%s\0' "$_FORGE_SESSION_MODEL"
    test -n "$_FORGE_SESSION_PROVIDER"; and printf 'FORGE_SESSION__PROVIDER_ID=%s\0' "$_FORGE_SESSION_PROVIDER"
    test -n "$_FORGE_SESSION_REASONING_EFFORT"; and printf 'FORGE_REASONING__EFFORT=%s\0' "$_FORGE_SESSION_REASONING_EFFORT"

    # Expose the terminal context lists as US-separated (\x1F) values so the
    # Rust TerminalContextService can read them. ASCII Unit Separator is used
    # instead of `:` because commands can legitimately contain colons (URLs,
    # port mappings, paths). `string collect` keeps multi-line commands in a
    # single value.
    if test "$_FORGE_TERM" = true; and test (count $_FORGE_TERM_COMMANDS) -gt 0
        printf '_FORGE_TERM_COMMANDS=%s\0' (string join \x1f -- $_FORGE_TERM_COMMANDS | string collect)
        printf '_FORGE_TERM_EXIT_CODES=%s\0' (string join \x1f -- $_FORGE_TERM_EXIT_CODES | string collect)
        printf '_FORGE_TERM_TIMESTAMPS=%s\0' (string join \x1f -- $_FORGE_TERM_TIMESTAMPS | string collect)
    end
    return 0
end

# Prints the agent forge should run with: the session agent, or `forge`.
function __forge_agent_id --description 'Print the active agent id'
    if test -n "$_FORGE_ACTIVE_AGENT"
        echo $_FORGE_ACTIVE_AGENT
    else
        echo forge
    end
end

# Executes forge with the active agent and session context. Output goes to
# the caller's stdout so results can be captured with `(...)`.
function __forge_exec --description 'Run forge with the active agent and session context'
    command env (__forge_session_env | string split0) $_FORGE_BIN --agent (__forge_agent_id) $argv
end

# Like __forge_exec but with stdin/stdout on the terminal so that interactive
# prompts (rustyline, nucleo-picker, tool approvals) work when forge runs from
# a key binding. Do NOT use inside `(...)` command substitutions.
function __forge_exec_interactive --description 'Run forge with the terminal attached'
    command env (__forge_session_env | string split0) $_FORGE_BIN --agent (__forge_agent_id) $argv </dev/tty >/dev/tty
end

# Interactive picker (`forge select …`) honouring the session overrides. The
# picker draws on stderr and prints the selection on stdout.
function __forge_select --description 'Run the forge picker with session context'
    command env (__forge_session_env | string split0) CLICOLOR_FORCE=0 $_FORGE_BIN select $argv </dev/tty 2>/dev/tty
end

# Interactive picker ignoring the session overrides (global config actions).
function __forge_select_global --description 'Run the forge picker with global config'
    CLICOLOR_FORCE=0 command $_FORGE_BIN select $argv </dev/tty 2>/dev/tty
end

# __forge_select_with_query <query> <select args…>
function __forge_select_with_query
    set -l query $argv[1]
    set -e argv[1]
    if test -n "$query"
        __forge_select $argv --query $query
    else
        __forge_select $argv
    end
end

# __forge_select_with_query_global <query> <select args…>
function __forge_select_with_query_global
    set -l query $argv[1]
    set -e argv[1]
    if test -n "$query"
        __forge_select_global $argv --query $query
    else
        __forge_select_global $argv
    end
end

# Picks a model and prints "<model_id>" and "<provider_id>" on two lines.
# Returns 1 when the picker is cancelled.
function __forge_select_model_pair
    set -l result (__forge_select_with_query "$argv[1]" model)
    test (count $result) -ge 2; or return 1
    printf '%s\n' $result[1] $result[2]
end

# Global-config variant of __forge_select_model_pair.
function __forge_select_model_pair_global
    set -l result (__forge_select_with_query_global "$argv[1]" model)
    test (count $result) -ge 2; or return 1
    printf '%s\n' $result[1] $result[2]
end

# Clears the command line and redraws the prompt below the output.
function __forge_reset --description 'Clear the command line and repaint the prompt'
    commandline -r ''
    commandline -f repaint
end

# Replaces the command line with $argv (used by :suggest, :commit-preview and
# :edit). Outside a key binding — the stub fallback path — the command line
# cannot be edited, so the text is printed instead.
function __forge_set_buffer --description 'Replace the command line with the given text'
    set -l text (string join ' ' -- $argv)
    if test "$__forge_in_binding" = 1
        commandline -r -- "$text"
        commandline -C (string length -- "$text")
        commandline -f repaint
        set -g __forge_keep_buffer 1
    else
        printf '%s\n' "$text"
    end
end

# Prints a message with consistent formatting.
# Usage: __forge_log <level> <message>
# Levels: error, info, success, warning, debug
# Colour scheme matches crates/forge_main/src/title_display.rs
function __forge_log --description 'Print a formatted log line: __forge_log <level> <message>'
    set -l level $argv[1]
    set -l message (string join ' ' -- $argv[2..-1])
    set -l timestamp (set_color brblack)'['(date '+%H:%M:%S')']'(set_color normal)

    switch $level
        case error
            # Category::Error - Red ⏺
            printf '%s⏺%s %s %s%s%s\n' (set_color red) (set_color normal) $timestamp (set_color red) "$message" (set_color normal)
        case info
            # Category::Info - White ⏺
            printf '%s⏺%s %s %s%s%s\n' (set_color white) (set_color normal) $timestamp (set_color white) "$message" (set_color normal)
        case success
            # Category::Action/Completion - Yellow ⏺
            printf '%s⏺%s %s %s%s%s\n' (set_color yellow) (set_color normal) $timestamp (set_color white) "$message" (set_color normal)
        case warning
            # Category::Warning - Bright yellow ⚠️
            printf '%s⚠️%s %s %s%s%s\n' (set_color bryellow) (set_color normal) $timestamp (set_color bryellow) "$message" (set_color normal)
        case debug
            # Category::Debug - Cyan ⏺ with dimmed text
            printf '%s⏺%s %s %s%s%s\n' (set_color cyan) (set_color normal) $timestamp (set_color brblack) "$message" (set_color normal)
        case '*'
            printf '%s\n' "$message"
    end
end

# Returns 0 when the workspace at $argv[1] has been indexed.
function __forge_is_workspace_indexed
    command $_FORGE_BIN workspace info $argv[1] >/dev/null 2>&1
end

# Starts a background sync of the current workspace when it is indexed.
# The work runs in a detached child fish so it never shows up in this
# session's job list and cannot write to the terminal.
function __forge_start_background_sync --description 'Sync the current workspace in the background'
    set -l sync_enabled true
    if set -q FORGE_SYNC_ENABLED; and test -n "$FORGE_SYNC_ENABLED"
        set sync_enabled $FORGE_SYNC_ENABLED
    end
    test "$sync_enabled" = true; or return 0

    set -l workspace_path (pwd -P)
    fish --no-config -c 'command $argv[1] workspace info $argv[2] >/dev/null 2>&1; or exit 0; command $argv[1] workspace sync $argv[2] >/dev/null 2>&1 </dev/null' $_FORGE_BIN $workspace_path >/dev/null 2>&1 </dev/null &
    disown 2>/dev/null
end

# Silently checks for and applies updates in the background.
function __forge_start_background_update --description 'Check for forge updates in the background'
    fish --no-config -c 'command $argv[1] update --no-confirm >/dev/null 2>&1 </dev/null' $_FORGE_BIN >/dev/null 2>&1 </dev/null &
    disown 2>/dev/null
end
