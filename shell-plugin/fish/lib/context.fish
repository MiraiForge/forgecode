#!/usr/bin/env fish

# Terminal context capture for the forge fish plugin
#
# 1. fish_preexec/fish_postexec hooks: ring buffer of recent commands + exit codes
# 2. OSC 133 emission around intercepted `:` commands (fish >= 4 marks the
#    prompt itself; a `:` line never reaches fish's executor, so the plugin
#    emits the command-output markers for it)

# ---------------------------------------------------------------------------
# OSC 133 helpers
# ---------------------------------------------------------------------------

# Determines whether OSC 133 markers should be emitted. The result is cached
# per session in _FORGE_TERM_OSC133_CACHED ("1" = emit, "0" = don't).
function __forge_osc133_should_emit
    if test -n "$_FORGE_TERM_OSC133_CACHED"
        test "$_FORGE_TERM_OSC133_CACHED" = 1
        return
    end

    switch "$_FORGE_TERM_OSC133"
        case on
            set -g _FORGE_TERM_OSC133_CACHED 1
            return 0
        case auto
            # fish >= 4.0 marks prompts natively unless the mark-prompt feature
            # is disabled, so pairing our command markers with it is safe.
            # fish 3.x never emits the prompt-start marker and unpaired
            # markers are worse than none, so stay silent there.
            if test "$_FORGE_FISH_MAJOR" -ge 4
                status test-feature mark-prompt 2>/dev/null
                if test $status -ne 1
                    set -g _FORGE_TERM_OSC133_CACHED 1
                    return 0
                end
            end
    end

    set -g _FORGE_TERM_OSC133_CACHED 0
    return 1
end

# Emits an OSC 133 marker if enabled.
# Usage: __forge_osc133_emit C  or  __forge_osc133_emit "D;0"
function __forge_osc133_emit
    __forge_osc133_should_emit; or return 0
    printf '\e]133;%s\a' $argv[1]
end

# ---------------------------------------------------------------------------
# fish_preexec / fish_postexec hooks
# ---------------------------------------------------------------------------

# Ring buffer storage uses parallel lists declared in config.fish:
#   _FORGE_TERM_COMMANDS, _FORGE_TERM_EXIT_CODES, _FORGE_TERM_TIMESTAMPS

# Called right before an interactive command runs; records it and the time.
function __forge_context_preexec --on-event fish_preexec
    test "$_FORGE_TERM" = true; or return 0
    set -g _FORGE_TERM_PENDING_CMD $argv[1]
    set -g _FORGE_TERM_PENDING_TS (date +%s)
end

# Called right after an interactive command finishes; captures its exit code
# and pushes the entry onto the ring buffer.
function __forge_context_postexec --on-event fish_postexec
    set -l last_status $status # MUST be the first statement
    test "$_FORGE_TERM" = true; or return 0
    test -n "$_FORGE_TERM_PENDING_CMD"; or return 0

    set -ga _FORGE_TERM_COMMANDS $_FORGE_TERM_PENDING_CMD
    set -ga _FORGE_TERM_EXIT_CODES $last_status
    set -ga _FORGE_TERM_TIMESTAMPS $_FORGE_TERM_PENDING_TS

    # Trim the ring buffer to its maximum size
    while test (count $_FORGE_TERM_COMMANDS) -gt $_FORGE_TERM_MAX_COMMANDS
        set -e _FORGE_TERM_COMMANDS[1]
        set -e _FORGE_TERM_EXIT_CODES[1]
        set -e _FORGE_TERM_TIMESTAMPS[1]
    end

    set -g _FORGE_TERM_PENDING_CMD ''
    set -g _FORGE_TERM_PENDING_TS ''
end
