#!/usr/bin/env fish

# Core action handlers for basic forge operations

# Action handler: Start a new conversation
function __forge_action_new
    set -l input_text $argv[1]

    # Clear conversation and save as previous (like cd -)
    __forge_clear_conversation
    set -g _FORGE_ACTIVE_AGENT forge

    echo

    if test -n "$input_text"
        # Generate new conversation ID and switch to it
        set -l new_id (command $_FORGE_BIN conversation new)
        __forge_switch_conversation $new_id

        __forge_exec_interactive -p "$input_text" --cid $_FORGE_CONVERSATION_ID

        __forge_start_background_sync
        __forge_start_background_update
    else
        # Only show banner when starting a fresh conversation without a prompt
        __forge_exec banner
    end
end

# Action handler: Show session info
function __forge_action_info
    echo
    if test -n "$_FORGE_CONVERSATION_ID"
        __forge_exec info --cid $_FORGE_CONVERSATION_ID
    else
        __forge_exec info
    end
end

# Action handler: Dump conversation (JSON, or HTML with `:dump html`)
function __forge_action_dump
    if test "$argv[1]" = html
        __forge_handle_conversation_command dump --html
    else
        __forge_handle_conversation_command dump
    end
end

# Action handler: Compact conversation
function __forge_action_compact
    __forge_handle_conversation_command compact
end

# Action handler: Retry last message
function __forge_action_retry
    __forge_handle_conversation_command retry
end

# Action handler: Show available commands (mirrors :help in the REPL)
function __forge_action_help
    echo
    command $_FORGE_BIN list command
end

# Runs a conversation subcommand that requires an active conversation.
# Usage: __forge_handle_conversation_command <subcommand> [extra args…]
function __forge_handle_conversation_command
    set -l subcommand $argv[1]
    set -e argv[1]

    echo

    if test -z "$_FORGE_CONVERSATION_ID"
        __forge_log error "No active conversation. Start a conversation first or use :conversation to see existing ones"
        return 0
    end

    __forge_exec conversation $subcommand $_FORGE_CONVERSATION_ID $argv
end
