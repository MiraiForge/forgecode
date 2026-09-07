#!/usr/bin/env fish

# Main command dispatcher and Enter-key widget

# Action handler: set the active agent, run a custom command, or send a prompt
# Flow:
# 1. If user_action is a CUSTOM command -> execute it with `cmd execute`
# 2. If no input_text -> switch to the agent (AGENT type commands only)
# 3. If input_text -> send the prompt with the active agent context
function __forge_action_default
    set -l user_action $argv[1]
    set -l input_text $argv[2]
    set -l command_type ''

    # Validate that the command exists in the command catalogue
    if test -n "$user_action"
        set -l commands_list (__forge_get_commands)
        if test -n "$commands_list"
            set -l pattern '^'(string escape --style=regex -- $user_action)'\b.*'
            set -l command_row (printf '%s\n' $commands_list | string match -r -- $pattern)
            if test -z "$command_row"
                echo
                __forge_log error "Command '"(set_color --bold)$user_action(set_color normal)"' not found"
                return 0
            end

            # Format: "COMMAND_NAME    TYPE    DESCRIPTION"
            set command_type (string lower -- (string split -n ' ' -- $command_row[1])[2])
            if test "$command_type" = custom
                # Generate a conversation ID if needed (don't track previous)
                if test -z "$_FORGE_CONVERSATION_ID"
                    set -g _FORGE_CONVERSATION_ID (command $_FORGE_BIN conversation new)
                end

                echo
                if test -n "$input_text"
                    __forge_exec cmd execute --cid $_FORGE_CONVERSATION_ID $user_action $input_text
                else
                    __forge_exec cmd execute --cid $_FORGE_CONVERSATION_ID $user_action
                end
                return 0
            end
        end
    end

    # No input text: switch the active agent (AGENT type commands only)
    if test -z "$input_text"
        if test -n "$user_action"
            if test "$command_type" != agent
                echo
                __forge_log error "Command '"(set_color --bold)$user_action(set_color normal)"' not found"
                return 0
            end
            echo
            set -g _FORGE_ACTIVE_AGENT $user_action
            __forge_log info (set_color --bold white)(string upper -- $_FORGE_ACTIVE_AGENT)(set_color normal)' '(set_color brblack)'is now the active agent'(set_color normal)
        end
        return 0
    end

    # Generate a conversation ID if needed (don't track previous)
    if test -z "$_FORGE_CONVERSATION_ID"
        set -g _FORGE_CONVERSATION_ID (command $_FORGE_BIN conversation new)
    end

    echo

    # Only set the agent if the user explicitly specified one
    test -n "$user_action"; and set -g _FORGE_ACTIVE_AGENT $user_action

    __forge_exec_interactive -p "$input_text" --cid $_FORGE_CONVERSATION_ID

    __forge_start_background_sync
    __forge_start_background_update
end

# Dispatches one parsed `:` command.
# $argv[1] = command name (empty for `: prompt`), $argv[2] = remaining text.
#
# ⚠️  IMPORTANT: keep this switch in sync with shell-plugin/lib/dispatcher.zsh
#     and the REPL commands in crates/forge_main/src/model.rs.
function __forge_dispatch
    set -l user_action $argv[1]
    set -l input_text $argv[2]

    # Aliases → agent names
    switch $user_action
        case ask
            set user_action sage
        case plan
            set user_action muse
    end

    switch $user_action
        case '*'
            __forge_action_default "$user_action" "$input_text"
    end
end

# Enter-key widget: routes `:` lines to Forge and executes everything else.
function __forge_accept_line --description 'Enter: route :commands to Forge, execute everything else'
    set -l buffer (commandline -b | string collect)

    set -l user_action ''
    set -l input_text ''
    if string match -qr -- '(?s)^:[a-zA-Z][a-zA-Z0-9_-]*( .*)?$' "$buffer"
        # Action with or without parameters: `:foo` or `:foo bar baz`
        set user_action (string match -r -- '^:([a-zA-Z][a-zA-Z0-9_-]*)' "$buffer")[2]
        set input_text (string replace -r -- '(?s)^:[a-zA-Z][a-zA-Z0-9_-]*( |$)' '' "$buffer" | string collect)
    else if string match -qr -- '(?s)^: .*$' "$buffer"
        # Default action with parameters: `: something`
        set input_text (string replace -r -- '^: ' '' "$buffer" | string collect)
    else
        # Not a forge command: normal execution
        commandline -f execute
        return
    end

    # Keep the raw line in history; fish only records lines it executes itself.
    if test "$_FORGE_FISH_MAJOR" -ge 4
        history append "$buffer" 2>/dev/null
    end

    # Move the cursor past the buffer so output starts below the prompt line
    commandline -C (string length -- "$buffer")
    commandline -f repaint

    set -g __forge_in_binding 1
    set -g __forge_keep_buffer 0

    # Intercepted lines never reach fish's executor, so emit the OSC 133
    # command-output markers explicitly; fish emits the prompt markers itself.
    __forge_osc133_emit C
    __forge_dispatch "$user_action" "$input_text"
    set -l action_status $status
    __forge_osc133_emit "D;$action_status"

    set -g __forge_in_binding 0
    if test "$__forge_keep_buffer" = 1
        # The action replaced the command line (:suggest, :commit-preview, :edit)
        set -g __forge_keep_buffer 0
    else
        __forge_reset
    end
    return $action_status
end

# Fallback dispatch used by the `:name` stub functions when a `:` line is
# executed without going through the Enter binding (scripts, other plugins).
# Arguments have already been through fish's parser, so quoting and globs
# are lost; this path is best effort only.
function __forge_dispatch_argv --description 'Fallback dispatch used by the :command stubs'
    set -l user_action $argv[1]
    set -e argv[1]
    set -l input_text (string join ' ' -- $argv)
    set -g __forge_in_binding 0
    set -g __forge_keep_buffer 0
    __forge_dispatch "$user_action" "$input_text"
end
