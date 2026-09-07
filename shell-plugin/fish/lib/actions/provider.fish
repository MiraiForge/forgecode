#!/usr/bin/env fish

# Provider selection action handlers

# Action handler: Select the provider for the current session only.
# Sets _FORGE_SESSION_PROVIDER so every subsequent forge invocation uses it
# without touching the permanent global configuration.
function __forge_action_session_provider
    echo

    set -l selected (__forge_select_with_query "$argv[1]" provider)
    if test -n "$selected"
        set -g _FORGE_SESSION_PROVIDER $selected
        __forge_log success "Session provider set to "(set_color --bold)$selected(set_color normal)
    end
end
