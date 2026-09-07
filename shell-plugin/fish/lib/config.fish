#!/usr/bin/env fish

# Configuration variables for the forge fish plugin.
#
# State is kept in global variables (`set -g`), never universal ones, so every
# terminal session has its own conversation, agent and session overrides.
# Values that may already exist (a re-sourced plugin) are left untouched.

# Sets `$argv[1]` from the environment variable named `$argv[2]`, falling
# back to `$argv[3]` when it is unset or empty.
function __forge_setting
    set -l name $argv[1]
    set -l env_name $argv[2]
    set -l default $argv[3]
    if set -q $env_name; and test -n "$$env_name"
        set -g $name $$env_name
    else
        set -g $name $default
    end
end

__forge_setting _FORGE_BIN FORGE_BIN forge
__forge_setting _FORGE_MAX_COMMIT_DIFF FORGE_MAX_COMMIT_DIFF 100000

# Terminal context capture settings
# Master switch for terminal context capture (preexec/postexec hooks)
__forge_setting _FORGE_TERM FORGE_TERM true
# Maximum number of commands to keep in the ring buffer (metadata: cmd + exit code)
__forge_setting _FORGE_TERM_MAX_COMMANDS FORGE_TERM_MAX_COMMANDS 5
# OSC 133 semantic prompt marker emission: "auto", "on", or "off"
__forge_setting _FORGE_TERM_OSC133 FORGE_TERM_OSC133 auto

set -g _FORGE_CONVERSATION_PATTERN ':'

# Cached output of `forge list commands --porcelain` (lazily populated)
set -q _FORGE_COMMANDS; or set -g _FORGE_COMMANDS ''

# Session state, only ever touched through the plugin
set -q _FORGE_CONVERSATION_ID; or set -g _FORGE_CONVERSATION_ID ''
set -q _FORGE_ACTIVE_AGENT; or set -g _FORGE_ACTIVE_AGENT ''

# Previous conversation ID for `:conversation -` (like cd -)
set -q _FORGE_PREVIOUS_CONVERSATION_ID; or set -g _FORGE_PREVIOUS_CONVERSATION_ID ''

# Session-scoped model, provider and reasoning effort overrides
# (set via :model / :m and :reasoning-effort / :re)
set -q _FORGE_SESSION_MODEL; or set -g _FORGE_SESSION_MODEL ''
set -q _FORGE_SESSION_PROVIDER; or set -g _FORGE_SESSION_PROVIDER ''
set -q _FORGE_SESSION_REASONING_EFFORT; or set -g _FORGE_SESSION_REASONING_EFFORT ''

# Ring buffer lists for terminal context capture
set -q _FORGE_TERM_COMMANDS; or set -g _FORGE_TERM_COMMANDS
set -q _FORGE_TERM_EXIT_CODES; or set -g _FORGE_TERM_EXIT_CODES
set -q _FORGE_TERM_TIMESTAMPS; or set -g _FORGE_TERM_TIMESTAMPS
set -g _FORGE_TERM_PENDING_CMD ''
set -g _FORGE_TERM_PENDING_TS ''
set -g _FORGE_TERM_OSC133_CACHED ''

# Major fish version: history append, named keys and native OSC 133 prompt
# marking all arrived in fish 4.0.
set -g _FORGE_FISH_MAJOR (string split . -- $version)[1]
