#!/usr/bin/env fish

# Editor and command suggestion action handlers

# Action handler: Compose a prompt in an external editor
# Usage: :edit [initial text]
function __forge_action_editor
    set -l initial_text $argv[1]

    echo

    set -l editor_cmd (__forge_editor_command)
    if not command -q (string split ' ' -- $editor_cmd)[1]
        __forge_log error "Editor not found: $editor_cmd (set FORGE_EDITOR or EDITOR)"
        return 1
    end

    # Temporary file lives in .forge, like git's COMMIT_EDITMSG
    set -l forge_dir .forge
    if not test -d $forge_dir
        mkdir -p $forge_dir
        or begin
            __forge_log error "Failed to create .forge directory"
            return 1
        end
    end

    set -l temp_file $forge_dir/FORGE_EDITMSG.md
    touch $temp_file
    or begin
        __forge_log error "Failed to create temporary file"
        return 1
    end

    test -n "$initial_text"; and printf '%s\n' "$initial_text" >$temp_file

    __forge_run_editor $editor_cmd $temp_file
    set -l editor_exit_code $status

    if test $editor_exit_code -ne 0
        rm -f $temp_file
        __forge_log error "Editor exited with error code $editor_exit_code"
        return 1
    end

    set -l content (cat $temp_file | tr -d '\r' | string collect)
    rm -f $temp_file

    if test -z "$content"
        __forge_log info "Editor closed with no content"
        return 0
    end

    # Put the prompt in the command line with the : prefix
    __forge_set_buffer ": $content"
end

# Action handler: Generate a shell command from natural language
# Usage: :suggest <description>
function __forge_action_suggest
    set -l description $argv[1]

    if test -z "$description"
        __forge_log error "Please provide a command description"
        return 0
    end

    echo

    set -l generated_command (FORCE_COLOR=true CLICOLOR_FORCE=1 __forge_exec suggest $description | string collect)

    if test -n "$generated_command"
        __forge_set_buffer "$generated_command"
    else
        __forge_log error "Failed to generate command"
    end
end
