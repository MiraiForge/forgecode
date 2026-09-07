#!/usr/bin/env fish

# Fish Keyboard Shortcuts - shows the fish line editor shortcuts relevant to Forge

function __kb_bold
    echo (set_color --bold)"$argv"(set_color normal)
end
function __kb_dim
    echo (set_color brblack)"$argv"(set_color normal)
end
function __kb_cyan
    echo (set_color cyan)"$argv"(set_color normal)
end

# Prints a section header
function print_section
    echo
    echo (__kb_bold $argv[1])
end

# Prints a shortcut with the description aligned in a 20-column key field.
# With a single argument the text is printed dimmed (configuration lines).
function print_shortcut
    set -l key $argv[1]
    set -l description $argv[2]

    if test -z "$description"
        echo "  "(__kb_dim $key)
        return
    end

    set -l pad (math "max(0, 20 - "(string length -- $key)")")
    printf '  %s%s%s\n' (__kb_cyan $key) (string repeat -n $pad ' ') $description
end

# Detect platform
set -l platform unknown
set -l alt_key Alt
switch (uname)
    case Darwin
        set platform macOS
        set alt_key Option
    case Linux
        set platform Linux
    case 'MINGW*' 'MSYS*' 'CYGWIN*'
        set platform Windows
end

# Detect vi mode
set -l vi_mode false
if contains -- "$fish_key_bindings" fish_vi_key_bindings fish_hybrid_key_bindings
    set vi_mode true
end

print_section Configuration
test "$platform" != unknown; and print_shortcut "Platform: $platform"
if test "$vi_mode" = true
    print_shortcut "Mode: Vi keybindings ($fish_key_bindings)"
else
    print_shortcut "Mode: Emacs keybindings (default)"
end

print_section Forge
print_shortcut Enter "Send :commands to Forge, run everything else"
print_shortcut "@ then Tab" "Pick a file to attach as @[path]"
print_shortcut ": then Tab" "Pick a :command"

if test "$vi_mode" = true
    print_section "Mode Switching"
    print_shortcut "Escape" "Enter normal mode"
    print_shortcut i "Enter insert mode"
    print_shortcut a "Enter insert mode (after cursor)"
    print_shortcut A "Enter insert mode (end of line)"
    print_shortcut I "Enter insert mode (start of line)"
    print_shortcut v "Enter visual mode"

    print_section "Navigation (Normal Mode)"
    print_shortcut w "Move forward one word"
    print_shortcut b "Move backward one word"
    print_shortcut "0 / ^" "Move to beginning of line"
    print_shortcut '$' "Move to end of line"
    print_shortcut "gg / G" "Move to start / end of buffer"

    print_section "Editing (Normal Mode)"
    print_shortcut dd "Delete entire line"
    print_shortcut D "Delete from cursor to end of line"
    print_shortcut cc "Change entire line"
    print_shortcut C "Change from cursor to end of line"
    print_shortcut cw "Change word"
    print_shortcut dw "Delete word"
    print_shortcut x "Delete character"
    print_shortcut u "Undo"
    print_shortcut "Ctrl+R" "Redo"
    print_shortcut p "Paste after cursor"
    print_shortcut P "Paste before cursor"

    print_section "History (Normal Mode)"
    print_shortcut "k / ↑" "Previous command"
    print_shortcut "j / ↓" "Next command"
    print_shortcut "/" "Open the history pager"

    print_section "Insert Mode"
    print_shortcut "Ctrl+W" "Delete path component before cursor"
    print_shortcut "Ctrl+U" "Delete from cursor to start"
    print_shortcut "$alt_key+E" "Edit command in \$EDITOR"

    print_section Other
    print_shortcut "Ctrl+L" "Clear screen"
    print_shortcut "Ctrl+C" "Clear the command line"
    print_shortcut Tab "Complete command/path"
    print_shortcut "Shift+Tab" "Complete and search"
else
    print_section "Line Navigation"
    print_shortcut "Ctrl+A" "Move to beginning of line"
    print_shortcut "Ctrl+E" "Move to end of line"
    print_shortcut "$alt_key+F" "Move forward one word"
    print_shortcut "$alt_key+B" "Move backward one word"
    print_shortcut "$alt_key+<" "Move to start of buffer"
    print_shortcut "$alt_key+>" "Move to end of buffer"

    print_section Editing
    print_shortcut "Ctrl+U" "Kill line before cursor"
    print_shortcut "Ctrl+K" "Kill line after cursor"
    print_shortcut "Ctrl+W" "Kill path component before cursor"
    print_shortcut "$alt_key+Backspace" "Kill word before cursor"
    print_shortcut "$alt_key+D" "Kill word after cursor"
    print_shortcut "Ctrl+Y" "Yank (paste) killed text"
    print_shortcut "$alt_key+Y" "Cycle through the kill ring"
    print_shortcut "Ctrl+Z" "Undo last edit"
    print_shortcut "$alt_key+/" "Redo"
    print_shortcut "$alt_key+T" "Transpose words"
    print_shortcut "$alt_key+U / $alt_key+C" "Uppercase / capitalize word"

    print_section History
    print_shortcut "Ctrl+R" "Open the history pager"
    print_shortcut "Ctrl+P / ↑" "Previous command (prefix search)"
    print_shortcut "Ctrl+N / ↓" "Next command"
    print_shortcut "$alt_key+↑ / $alt_key+↓" "Search history tokens"
    print_shortcut "$alt_key+." "Insert last token of previous command"

    print_section Completion
    print_shortcut Tab "Complete command/path"
    print_shortcut "Shift+Tab" "Complete and search"
    print_shortcut "→ / Ctrl+F" "Accept autosuggestion"

    print_section Other
    print_shortcut "$alt_key+E / $alt_key+V" "Edit command in \$EDITOR"
    print_shortcut "$alt_key+L" "List the directory of the current token"
    print_shortcut "$alt_key+O" "Preview the file under the cursor"
    print_shortcut "$alt_key+H" "Open the man page for the current command"
    print_shortcut "$alt_key+W" "Describe the current command (whatis)"
    print_shortcut "$alt_key+S" "Prepend sudo"
    print_shortcut "Ctrl+X / Ctrl+V" "Copy / paste with the system clipboard"
    print_shortcut "Ctrl+L" "Clear screen"
    print_shortcut "Ctrl+C" "Clear the command line"
    print_shortcut "Ctrl+D" "Delete character or exit"

    echo
    if test "$platform" = macOS
        echo "  "(__kb_dim "If Option key shortcuts don't work, run: forge fish doctor")
    else if test "$platform" = Linux
        echo "  "(__kb_dim "If Alt key shortcuts don't work, run: forge fish doctor")
    end
    echo "  "(__kb_dim "To enable Vi mode, run: fish_vi_key_bindings (persist with: set -U fish_key_bindings fish_vi_key_bindings)")
end

echo
