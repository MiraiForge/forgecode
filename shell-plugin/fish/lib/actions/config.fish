#!/usr/bin/env fish

# Configuration action handlers (agent, provider, model, tools, skill)

# Action handler: Select agent
function __forge_action_agent
    set -l input_text $argv[1]

    echo

    # An agent ID was provided directly: validate it against the registry
    if test -n "$input_text"
        set -l pattern '^'(string escape --style=regex -- $input_text)'\b'
        if not command $_FORGE_BIN list agents --porcelain 2>/dev/null | tail -n +2 | string match -qr -- $pattern
            __forge_log error "Agent '"(set_color --bold)$input_text(set_color normal)"' not found"
            return 0
        end

        set -g _FORGE_ACTIVE_AGENT $input_text
        __forge_log success "Switched to agent "(set_color --bold)$input_text(set_color normal)
        return 0
    end

    set -l agent_id (__forge_select_with_query "$input_text" agent)
    if test -n "$agent_id"
        set -g _FORGE_ACTIVE_AGENT $agent_id
        __forge_log success "Switched to agent "(set_color --bold)$agent_id(set_color normal)
    end
end

# Action handler: Set the global model (:config-model). When the selected
# model belongs to a different provider, the provider is switched as well.
function __forge_action_model
    echo

    set -l pair (__forge_select_model_pair_global "$argv[1]")
    test (count $pair) -ge 2; or return 0
    __forge_exec config set model $pair[2] $pair[1]
end

# Action handler: Set the model used for commit message generation
function __forge_action_commit_model
    echo

    set -l pair (__forge_select_model_pair "$argv[1]")
    test (count $pair) -ge 2; or return 0
    __forge_exec config set commit $pair[2] $pair[1]
end

# Action handler: Set the model used for command suggestion generation
function __forge_action_suggest_model
    echo

    set -l pair (__forge_select_model_pair "$argv[1]")
    test (count $pair) -ge 2; or return 0
    __forge_exec config set suggest $pair[2] $pair[1]
end

# Action handler: Sync workspace for codebase search (initialises it first
# when needed; the consent prompt needs the terminal)
function __forge_action_sync
    echo
    __forge_exec_interactive workspace sync --init
end

# Action handler: Initialise the workspace for codebase search
function __forge_action_sync_init
    echo
    __forge_exec_interactive workspace init
end

# Action handler: Show sync status of workspace files
function __forge_action_sync_status
    echo
    __forge_exec workspace status .
end

# Action handler: Show workspace info with sync details
function __forge_action_sync_info
    echo
    __forge_exec workspace info .
end

# Action handler: Set the model for the current session only (:model)
function __forge_action_session_model
    echo

    set -l pair (__forge_select_model_pair "$argv[1]")
    test (count $pair) -ge 2; or return 0
    set -g _FORGE_SESSION_MODEL $pair[1]
    set -g _FORGE_SESSION_PROVIDER $pair[2]
    __forge_log success "Session model set to "(set_color --bold)$_FORGE_SESSION_MODEL(set_color normal)" (provider: "(set_color --bold)$_FORGE_SESSION_PROVIDER(set_color normal)")"
end

# Action handler: Clear all session-scoped overrides (:config-reload)
function __forge_action_config_reload
    echo

    if test -z "$_FORGE_SESSION_MODEL"; and test -z "$_FORGE_SESSION_PROVIDER"; and test -z "$_FORGE_SESSION_REASONING_EFFORT"
        __forge_log info "No session overrides active (already using global config)"
        return 0
    end

    set -g _FORGE_SESSION_MODEL ''
    set -g _FORGE_SESSION_PROVIDER ''
    set -g _FORGE_SESSION_REASONING_EFFORT ''

    __forge_log success "Session overrides cleared — using global config"
end

# Action handler: Set the reasoning effort for the current session only
function __forge_action_reasoning_effort
    echo

    set -l selected (__forge_select_with_query "$argv[1]" reasoning-effort)
    if test -n "$selected"
        set -g _FORGE_SESSION_REASONING_EFFORT $selected
        __forge_log success "Session reasoning effort set to "(set_color --bold)$selected(set_color normal)
    end
end

# Action handler: Set the reasoning effort in the global config
function __forge_action_config_reasoning_effort
    echo

    set -l selected (__forge_select_with_query "$argv[1]" reasoning-effort)
    test -n "$selected"; and __forge_exec config set reasoning-effort $selected
end

# Action handler: Show the effective configuration
function __forge_action_config
    echo
    __forge_exec config list
end

# Prints the editor command: FORGE_EDITOR > EDITOR > nano
function __forge_editor_command
    if set -q FORGE_EDITOR; and test -n "$FORGE_EDITOR"
        echo $FORGE_EDITOR
    else if set -q EDITOR; and test -n "$EDITOR"
        echo $EDITOR
    else
        echo nano
    end
end

# Runs the editor command on a file with the terminal attached.
# Usage: __forge_run_editor <editor command> <file>
function __forge_run_editor
    eval $argv[1] (string escape -- $argv[2]) '</dev/tty >/dev/tty 2>&1'
end

# Action handler: Open the global forge config file in an editor
function __forge_action_config_edit
    echo

    set -l editor_cmd (__forge_editor_command)
    if not command -q (string split ' ' -- $editor_cmd)[1]
        __forge_log error "Editor not found: $editor_cmd (set FORGE_EDITOR or EDITOR)"
        return 1
    end

    # Resolve the config file path via forge (honours FORGE_CONFIG and the
    # legacy ~/forge fallback automatically)
    set -l config_file (command $_FORGE_BIN config path 2>/dev/null)
    if test -z "$config_file"
        __forge_log error "Failed to resolve config path from '$_FORGE_BIN config path'"
        return 1
    end

    set -l config_dir (dirname $config_file)
    if not test -d $config_dir
        mkdir -p $config_dir
        or begin
            __forge_log error "Failed to create $config_dir directory"
            return 1
        end
    end

    if not test -f $config_file
        touch $config_file
        or begin
            __forge_log error "Failed to create $config_file"
            return 1
        end
    end

    __forge_run_editor $editor_cmd $config_file
    set -l exit_code $status
    test $exit_code -ne 0; and __forge_log error "Editor exited with error code $exit_code"
    return 0
end

# Action handler: List tools for the active agent
function __forge_action_tools
    echo
    __forge_exec list tools (__forge_agent_id)
end

# Action handler: List skills
function __forge_action_skill
    echo
    __forge_exec list skill
end
