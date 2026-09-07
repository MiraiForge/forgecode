#!/usr/bin/env fish

# Git integration action handlers

# Quotes text as a fish single-quoted string for insertion in the command line
function __forge_squote
    set -l escaped (string replace -a -- '\\' '\\\\' "$argv[1]" | string replace -a -- "'" "\\'" | string collect)
    printf "'%s'" "$escaped"
end

# Action handler: Commit changes directly with an AI-generated message
# Usage: :commit [additional context]
function __forge_action_commit
    set -l additional_context $argv[1]

    echo

    # FORCE_COLOR / CLICOLOR_FORCE keep colours when forge is not on a tty
    if test -n "$additional_context"
        set -l commit_message (FORCE_COLOR=true CLICOLOR_FORCE=1 command $_FORGE_BIN commit --max-diff $_FORGE_MAX_COMMIT_DIFF (string split ' ' -- $additional_context))
    else
        set -l commit_message (FORCE_COLOR=true CLICOLOR_FORCE=1 command $_FORGE_BIN commit --max-diff $_FORGE_MAX_COMMIT_DIFF)
    end
end

# Action handler: Put an AI-generated commit command in the command line
# Usage: :commit-preview [additional context]
function __forge_action_commit_preview
    set -l additional_context $argv[1]

    echo

    set -l commit_message
    if test -n "$additional_context"
        set commit_message (FORCE_COLOR=true CLICOLOR_FORCE=1 command $_FORGE_BIN commit --preview --max-diff $_FORGE_MAX_COMMIT_DIFF (string split ' ' -- $additional_context) | string collect)
    else
        set commit_message (FORCE_COLOR=true CLICOLOR_FORCE=1 command $_FORGE_BIN commit --preview --max-diff $_FORGE_MAX_COMMIT_DIFF | string collect)
    end

    test -n "$commit_message"; or return 0

    # No staged changes: commit all tracked changes with -a
    if git diff --staged --quiet
        __forge_set_buffer "git commit -am "(__forge_squote "$commit_message")
    else
        __forge_set_buffer "git commit -m "(__forge_squote "$commit_message")
    end
end
