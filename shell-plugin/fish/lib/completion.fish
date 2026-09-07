#!/usr/bin/env fish

# Tab widget: `@` file picker and `:` command picker, else normal completion

function __forge_complete --description 'Tab: @file and :command pickers, otherwise complete'
    # @ completion (files and directories) on the token under the cursor
    set -l current_token (commandline -t)
    if string match -q -- '@*' "$current_token"
        set -l filter_text (string sub -s 2 -- "$current_token")

        # Use Rust's built-in file picker
        set -l selected (__forge_select_with_query "$filter_text" file)
        if test -n "$selected"
            commandline -t -- "@[$selected]"
        end

        commandline -f repaint
        return 0
    end

    # :command completion (letters, numbers, hyphens, underscores)
    set -l buffer (commandline -b | string collect)
    if string match -qr -- '^:([a-zA-Z][a-zA-Z0-9_-]*)?$' "$buffer"
        set -l filter_text (string sub -s 2 -- "$buffer")

        # Use Rust's built-in command picker
        set -l selected (__forge_select_with_query "$filter_text" command)
        if test -n "$selected"
            commandline -r -- ":$selected "
            commandline -C (string length -- ":$selected ")
        end

        commandline -f repaint
        return 0
    end

    # Fall back to fish's completion
    commandline -f complete
end
