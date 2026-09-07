#!/usr/bin/env fish

# Conversation management action handlers
#
# Features:
# - :conversation          - List and switch conversations (with interactive picker)
# - :conversation <id>     - Switch to specific conversation by ID
# - :conversation -        - Toggle between current and previous conversation (like cd -)
# - :conversation-tree     - Show nested conversations spawned by current conversation
# - :clone                 - Clone current or selected conversation
# - :clone <id>            - Clone specific conversation by ID
# - :copy                  - Copy last assistant message to OS clipboard as raw markdown
# - :rename <name>         - Rename the current conversation
# - :conversation-rename   - Rename a conversation (interactive picker)
# - :conversation-rename <id> <name> - Rename specific conversation by ID

# Switches to a conversation and tracks the previous one (like cd -)
function __forge_switch_conversation
    set -l new_conversation_id $argv[1]

    if test -n "$_FORGE_CONVERSATION_ID"; and test "$_FORGE_CONVERSATION_ID" != "$new_conversation_id"
        set -g _FORGE_PREVIOUS_CONVERSATION_ID $_FORGE_CONVERSATION_ID
    end

    set -g _FORGE_CONVERSATION_ID $new_conversation_id
end

# Clears the conversation and saves it as previous (like cd -)
function __forge_clear_conversation
    test -n "$_FORGE_CONVERSATION_ID"; and set -g _FORGE_PREVIOUS_CONVERSATION_ID $_FORGE_CONVERSATION_ID
    set -g _FORGE_CONVERSATION_ID ''
end

# Shows a conversation, its info and a "switched" log line
function __forge_show_switched_conversation
    set -l conversation_id $argv[1]

    echo
    __forge_exec conversation show $conversation_id
    __forge_exec conversation info $conversation_id
    __forge_log success "Switched to conversation "(set_color --bold)$conversation_id(set_color normal)
end

# Action handler: List/switch conversations
function __forge_action_conversation
    set -l input_text $argv[1]

    echo

    # Toggle to the previous conversation (like cd -)
    if test "$input_text" = -
        if test -z "$_FORGE_PREVIOUS_CONVERSATION_ID"
            # Nothing to toggle to: fall through to the picker
            set input_text ''
        else
            set -l temp $_FORGE_CONVERSATION_ID
            set -g _FORGE_CONVERSATION_ID $_FORGE_PREVIOUS_CONVERSATION_ID
            set -g _FORGE_PREVIOUS_CONVERSATION_ID $temp
            __forge_show_switched_conversation $_FORGE_CONVERSATION_ID
            return 0
        end
    end

    # An ID was provided directly
    if test -n "$input_text"
        __forge_switch_conversation $input_text
        __forge_show_switched_conversation $input_text
        return 0
    end

    # Use Rust's built-in conversation picker with preview
    set -l conversation_id (__forge_select conversation)
    if test -n "$conversation_id"
        __forge_switch_conversation $conversation_id
        __forge_show_switched_conversation $conversation_id
    end
end

# Action handler: Show nested conversations spawned by the current conversation
function __forge_action_conversation_tree
    __forge_select conversation --parent "$_FORGE_CONVERSATION_ID"
end

# Action handler: Clone conversation
function __forge_action_clone
    set -l clone_target $argv[1]

    echo

    if test -n "$clone_target"
        __forge_clone_and_switch $clone_target
        return 0
    end

    set -l conversation_id (__forge_select conversation)
    test -n "$conversation_id"; and __forge_clone_and_switch $conversation_id
end

# Action handler: Copy last assistant message to the OS clipboard as raw markdown
function __forge_action_copy
    echo

    if test -z "$_FORGE_CONVERSATION_ID"
        __forge_log error "No active conversation. Start a conversation first or use :conversation to see existing ones"
        return 0
    end

    set -l content (command $_FORGE_BIN conversation show --md $_FORGE_CONVERSATION_ID 2>/dev/null | string collect)
    if test -z "$content"
        __forge_log error "No assistant message found in the current conversation"
        return 0
    end

    # fish_clipboard_copy wraps pbcopy, xclip, xsel and wl-copy
    if not printf '%s' "$content" | fish_clipboard_copy
        __forge_log error "No clipboard utility found (pbcopy, xclip, xsel or wl-copy required)"
        return 0
    end

    set -l line_count (printf '%s\n' "$content" | wc -l | string trim)
    set -l byte_count (printf '%s' "$content" | wc -c | string trim)
    __forge_log success "Copied to clipboard "(set_color brblack)"[$line_count lines, $byte_count bytes]"(set_color normal)
end

# Action handler: Rename the current conversation
# Usage: :rename <name>
function __forge_action_rename
    set -l input_text $argv[1]

    echo

    if test -z "$_FORGE_CONVERSATION_ID"
        __forge_log error "No active conversation. Start a conversation first or use :conversation to select one"
        return 0
    end

    if test -z "$input_text"
        __forge_log error "Usage: :rename <name>"
        return 0
    end

    __forge_exec conversation rename $_FORGE_CONVERSATION_ID (string split ' ' -- $input_text)
end

# Action handler: Rename a conversation (interactive picker or by ID)
# Usage: :conversation-rename [<id> <name>]
function __forge_action_conversation_rename
    set -l input_text $argv[1]

    echo

    # "<id> <name>" provided: rename directly
    if test -n "$input_text"
        set -l parts (string split -m 1 ' ' -- $input_text)
        if test (count $parts) -lt 2
            __forge_log error "Usage: :conversation-rename <id> <name>"
            return 0
        end
        __forge_exec conversation rename $parts[1] (string split ' ' -- $parts[2])
        return 0
    end

    set -l conversation_id (__forge_select conversation)
    if test -n "$conversation_id"
        set -l new_name
        read -P 'Enter new name: ' new_name </dev/tty
        if test -n "$new_name"
            __forge_exec conversation rename $conversation_id (string split ' ' -- $new_name)
        else
            __forge_log error "No name provided, rename cancelled"
        end
    end
end

# Clones a conversation and switches to the clone
function __forge_clone_and_switch
    set -l clone_target $argv[1]
    set -l original_conversation_id $_FORGE_CONVERSATION_ID

    __forge_log info "Cloning conversation "(set_color --bold)$clone_target(set_color normal)
    set -l clone_output (command $_FORGE_BIN conversation clone $clone_target 2>&1)
    set -l clone_status $status

    if test $clone_status -eq 0
        # Extract the new conversation ID (last UUID in the output)
        set -l new_id (printf '%s\n' $clone_output | string match -r -a '[a-f0-9-]{36}')[-1]

        if test -n "$new_id"
            __forge_switch_conversation $new_id
            __forge_log success "└─ Switched to conversation "(set_color --bold)$new_id(set_color normal)

            # Show content and info only when cloning a different conversation
            if test "$clone_target" != "$original_conversation_id"
                echo
                __forge_exec conversation show $new_id
                echo
                __forge_exec conversation info $new_id
            end
        else
            __forge_log error "Failed to extract new conversation ID from clone output"
        end
    else
        __forge_log error "Failed to clone conversation: $clone_output"
    end
end
