#!/usr/bin/env fish

# Authentication action handlers

# Action handler: Login to a provider
function __forge_action_login
    echo

    set -l provider (__forge_select_with_query "$argv[1]" provider)
    test -n "$provider"; and __forge_exec_interactive provider login $provider
end

# Action handler: Logout from a provider
function __forge_action_logout
    echo

    set -l provider (__forge_select_with_query "$argv[1]" provider --configured)
    test -n "$provider"; and __forge_exec provider logout $provider
end
