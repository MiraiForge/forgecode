#!/usr/bin/env fish

# Forge right prompt for fish: agent, token count, cost, model and reasoning
# effort. All formatting is done by `forge fish rprompt`; this file only wires
# it into fish_right_prompt without discarding a right prompt the user (or a
# prompt framework loaded from config.fish) already defined.

# Renders the Forge segment. Session overrides are exported only for the
# child forge process so the rprompt reflects the active session state.
function __forge_prompt_info --description 'Render the Forge right prompt segment'
    set -l forge_bin forge
    if set -q _FORGE_BIN; and test -n "$_FORGE_BIN"
        set forge_bin $_FORGE_BIN
    else if set -q FORGE_BIN; and test -n "$FORGE_BIN"
        set forge_bin $FORGE_BIN
    end

    set -lx _FORGE_CONVERSATION_ID "$_FORGE_CONVERSATION_ID"
    set -lx _FORGE_ACTIVE_AGENT "$_FORGE_ACTIVE_AGENT"
    # fish keeps COLUMNS as an unexported global; forge reads it from the
    # environment to pick the compact or full reasoning effort label.
    set -lx COLUMNS "$COLUMNS"
    test -n "$_FORGE_SESSION_MODEL"; and set -lx FORGE_SESSION__MODEL_ID $_FORGE_SESSION_MODEL
    test -n "$_FORGE_SESSION_PROVIDER"; and set -lx FORGE_SESSION__PROVIDER_ID $_FORGE_SESSION_PROVIDER
    test -n "$_FORGE_SESSION_REASONING_EFFORT"; and set -lx FORGE_REASONING__EFFORT $_FORGE_SESSION_REASONING_EFFORT

    command $forge_bin fish rprompt 2>/dev/null
end

# Installs the Forge segment into fish_right_prompt at the first prompt, after
# config.fish and any prompt framework have had the chance to define their
# own right prompt. Runs once and then removes itself.
function __forge_install_right_prompt --on-event fish_prompt --description 'Wrap fish_right_prompt with the Forge segment (runs once)'
    functions -e __forge_install_right_prompt
    set -q _FORGE_RIGHT_PROMPT_INSTALLED; and return 0
    set -g _FORGE_RIGHT_PROMPT_INSTALLED 1

    if functions -q fish_right_prompt
        functions -c fish_right_prompt __forge_user_right_prompt
    end

    function fish_right_prompt --description 'Forge right prompt'
        __forge_prompt_info
        if functions -q __forge_user_right_prompt
            set -l user_prompt (__forge_user_right_prompt | string collect)
            test -n "$user_prompt"; and printf ' %s' "$user_prompt"
        end
    end
end
