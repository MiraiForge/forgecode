#!/usr/bin/env fish

# Fish Doctor - Diagnostic tool for the Forge shell environment
# Checks for common configuration issues and environment setup.
#
# Runs under `fish -c`: config.fish and conf.d are loaded, but the plugin
# only loads in interactive shells, so plugin checks look at the installed
# conf.d snippet and at the generated plugin rather than at live bindings.

function __doctor_bold
    echo (set_color --bold)"$argv"(set_color normal)
end
function __doctor_dim
    echo (set_color brblack)"$argv"(set_color normal)
end
function __doctor_green
    echo (set_color green)"$argv"(set_color normal)
end
function __doctor_red
    echo (set_color red)"$argv"(set_color normal)
end
function __doctor_yellow
    echo (set_color yellow)"$argv"(set_color normal)
end
function __doctor_cyan
    echo (set_color cyan)"$argv"(set_color normal)
end

# Simple ASCII symbols
set -g __doctor_pass "[OK]"
set -g __doctor_fail "[ERROR]"
set -g __doctor_warn "[WARN]"

# Counters
set -g __doctor_passed 0
set -g __doctor_failed 0
set -g __doctor_warnings 0

# Prints a section header
function print_section
    echo
    echo (__doctor_bold $argv[1])
end

# Prints a result line: print_result <pass|fail|warn|info|code|instruction> <message> [detail]
function print_result
    set -l result_status $argv[1]
    set -l message $argv[2]
    set -l detail $argv[3]

    switch $result_status
        case pass
            echo "  "(__doctor_green $__doctor_pass)" $message"
            set -g __doctor_passed (math $__doctor_passed + 1)
        case fail
            echo "  "(__doctor_red $__doctor_fail)" $message"
            test -n "$detail"; and echo "  "(__doctor_dim "· $detail")
            set -g __doctor_failed (math $__doctor_failed + 1)
        case warn
            echo "  "(__doctor_yellow $__doctor_warn)" $message"
            test -n "$detail"; and echo "  "(__doctor_dim "· $detail")
            set -g __doctor_warnings (math $__doctor_warnings + 1)
        case info code instruction
            echo "  "(__doctor_dim "· $message")
    end
end

# Returns 0 when version $argv[1] >= version $argv[2] (numeric prefixes only)
function __doctor_version_gte
    set -l v1 (string trim -l -c v -- $argv[1] | string split .)
    set -l v2 (string trim -l -c v -- $argv[2] | string split .)
    for i in 1 2 3
        set -l a (string replace -r -- '[^0-9].*$' '' "$v1[$i]")
        set -l b (string replace -r -- '[^0-9].*$' '' "$v2[$i]")
        test -n "$a"; or set a 0
        test -n "$b"; or set b 0
        if test $a -gt $b
            return 0
        else if test $a -lt $b
            return 1
        end
    end
    return 0
end

echo (__doctor_bold "FORGE ENVIRONMENT DIAGNOSTICS")

# 1. Shell environment
print_section "Shell Environment"
set -l fish_major (string split . -- $version)[1]
if test "$fish_major" -ge 4
    print_result pass "fish: $version"
else
    print_result warn "fish: $version" "Recommended: 4.0+ (history entries and OSC 133 markers for : commands need fish 4)"
end

if set -q TERM_PROGRAM; and test -n "$TERM_PROGRAM"
    if set -q TERM_PROGRAM_VERSION; and test -n "$TERM_PROGRAM_VERSION"
        print_result pass "Terminal: $TERM_PROGRAM $TERM_PROGRAM_VERSION"
    else
        print_result pass "Terminal: $TERM_PROGRAM"
    end
else if set -q TERM; and test -n "$TERM"
    print_result pass "Terminal: $TERM"
else
    print_result info "Terminal: unknown"
end

# 2. Forge installation
print_section "Forge Installation"
set -l forge_bin forge
if set -q FORGE_BIN; and test -n "$FORGE_BIN"
    set forge_bin $FORGE_BIN
end
set -l forge_available false
if command -q $forge_bin
    set forge_available true
    set -l forge_path (command -s $forge_bin)
    set -l forge_version (command $forge_bin --version 2>&1 | head -n1 | string split ' ')[2]
    if test -n "$forge_version"
        print_result pass "forge: $forge_version"
    else
        print_result pass "forge: installed"
    end
    print_result info "$forge_path"
else
    print_result fail "Forge binary not found in PATH" "Installation: curl -fsSL https://forgecode.dev/cli | sh"
end

# 3. Plugin
print_section Plugin
set -l conf_file $__fish_config_dir/conf.d/forge.fish
set -l conf_installed false
if test -f $conf_file; and grep -q 'fish plugin' $conf_file
    set conf_installed true
    print_result pass "Forge plugin installed"
    print_result info "$conf_file"
else
    print_result fail "Forge plugin not installed"
    print_result instruction "Run: forge fish setup"
    print_result instruction "Or add to $conf_file:"
    print_result code "forge fish plugin | source"
end

if functions -q __forge_accept_line
    print_result pass "Forge plugin loaded in this shell"
else if test "$conf_installed" = true
    print_result info "Loads in interactive shells (this check runs non-interactively)"
end

if test "$forge_available" = true
    if command $forge_bin fish plugin 2>/dev/null | fish --no-execute 2>/dev/null
        print_result pass "Generated plugin parses"
    else
        print_result fail "Generated plugin does not parse" "Run: forge fish plugin | fish --no-execute"
    end
end

# 4. Right prompt
print_section "FORGE RIGHT PROMPT"
if functions -q __forge_prompt_info
    print_result pass "Forge theme loaded"
else if test -f $conf_file; and grep -q 'fish theme' $conf_file
    print_result pass "Forge theme installed"
    print_result info "Adds a right prompt segment; an existing fish_right_prompt is kept"
else
    print_result warn "Forge theme not installed"
    print_result instruction "To use the Forge right prompt, add to $conf_file:"
    print_result code "forge fish theme | source"
end

# 5. Dependencies
print_section Dependencies

# Forge uses its built-in nucleo-picker for interactive selection
print_result pass "Interactive picker: built-in (nucleo-picker)"

# fd / fdfind - used for file discovery
if command -q fd
    set -l fd_version (fd --version 2>&1 | string split ' ')[2]
    if test -n "$fd_version"
        if __doctor_version_gte $fd_version 10.0.0
            print_result pass "fd: $fd_version"
        else
            print_result fail "fd: $fd_version" "Version 10.0.0 or higher required. Update: https://github.com/sharkdp/fd#installation"
        end
    else
        print_result pass "fd: installed"
    end
else if command -q fdfind
    set -l fd_version (fdfind --version 2>&1 | string split ' ')[2]
    if test -n "$fd_version"
        if __doctor_version_gte $fd_version 10.0.0
            print_result pass "fdfind: $fd_version"
        else
            print_result fail "fdfind: $fd_version" "Version 10.0.0 or higher required. Update: https://github.com/sharkdp/fd#installation"
        end
    else
        print_result pass "fdfind: installed"
    end
else
    print_result warn "fd/fdfind not found" "Enhanced file discovery. See installation: https://github.com/sharkdp/fd#installation"
end

# bat - used for syntax highlighting in previews
if command -q bat
    set -l bat_version (bat --version 2>&1 | string split ' ')[2]
    if test -n "$bat_version"
        if __doctor_version_gte $bat_version 0.20.0
            print_result pass "bat: $bat_version"
        else
            print_result fail "bat: $bat_version" "Version 0.20.0 or higher required. Update: https://github.com/sharkdp/bat#installation"
        end
    else
        print_result pass "bat: installed"
    end
else
    print_result warn "bat not found" "Enhanced preview. See installation: https://github.com/sharkdp/bat#installation"
end

# 6. Fish features (autosuggestions and syntax highlighting are built in)
print_section "Fish Features"
print_result pass "Autosuggestions and syntax highlighting: built into fish"
if contains -- "$fish_key_bindings" fish_vi_key_bindings fish_hybrid_key_bindings
    print_result pass "Key bindings: vi mode ($fish_key_bindings)"
else
    print_result pass "Key bindings: emacs mode (default)"
end

# 7. System configuration
print_section System

if set -q FORGE_EDITOR; and test -n "$FORGE_EDITOR"
    print_result pass "FORGE_EDITOR: $FORGE_EDITOR"
    if set -q EDITOR; and test -n "$EDITOR"
        print_result info "EDITOR also set: $EDITOR (ignored)"
    end
else if set -q EDITOR; and test -n "$EDITOR"
    print_result pass "EDITOR: $EDITOR"
    print_result info "TIP: Set FORGE_EDITOR for a forge-specific editor"
else
    print_result warn "No editor configured" "set -Ux EDITOR vim  or  set -Ux FORGE_EDITOR vim"
end

if contains -- /usr/local/bin $PATH; or contains -- /usr/bin $PATH
    print_result pass "PATH: configured"
else
    print_result warn "PATH may need common directories" "Ensure /usr/local/bin or /usr/bin is in PATH"
end

# 8. Keyboard configuration (Alt/Option key as Meta)
print_section "Keyboard Configuration"

set -l platform (uname)
set -l check_performed false

if test "$platform" = Darwin
    if test "$TERM_PROGRAM" = vscode
        set check_performed true
        set -l vscode_settings "$HOME/Library/Application Support/Code/User/settings.json"
        if test -f "$vscode_settings"
            if grep -q '"terminal.integrated.macOptionIsMeta"[[:space:]]*:[[:space:]]*true' "$vscode_settings" 2>/dev/null
                print_result pass "VS Code: Option key configured as Meta"
            else
                print_result warn "VS Code: Option key NOT configured as Meta"
                print_result instruction "Option+F and Option+B shortcuts won't work for word navigation"
                print_result instruction "Add to VS Code settings.json:"
                print_result code '"terminal.integrated.macOptionIsMeta": true'
                print_result instruction "Then reload VS Code: Cmd+Shift+P → Reload Window"
            end
        else
            print_result warn "VS Code settings file not found"
            print_result info "Expected: $vscode_settings"
        end
    else if test "$TERM_PROGRAM" = iTerm.app
        set check_performed true
        set -l iterm_prefs "$HOME/Library/Preferences/com.googlecode.iterm2.plist"
        if test -f "$iterm_prefs"
            set -l option_setting (defaults read com.googlecode.iterm2 2>/dev/null | grep -E '"(Left |Right )?Option Key Sends"' | grep -o '[0-9]' | head -1)
            if test "$option_setting" = 2
                print_result pass "iTerm2: Option key configured as Esc+"
            else
                print_result warn "iTerm2: Option key NOT configured as Esc+"
                print_result instruction "Option+F and Option+B shortcuts won't work for word navigation"
                print_result instruction "Configure in iTerm2:"
                print_result info "Preferences → Profiles → Keys → Left/Right Option Key → Esc+"
            end
        else
            print_result warn "iTerm2 preferences not found"
            print_result info "Expected: $iterm_prefs"
        end
    else if test "$TERM_PROGRAM" = Apple_Terminal
        set check_performed true
        set -l terminal_prefs "$HOME/Library/Preferences/com.apple.Terminal.plist"
        if test -f "$terminal_prefs"
            set -l use_option (defaults read com.apple.Terminal 2>/dev/null | grep -E 'useOptionAsMetaKey' | grep -o '[0-9]' | head -1)
            if test "$use_option" = 1
                print_result pass "Terminal.app: Option key configured as Meta"
            else
                print_result warn "Terminal.app: Option key NOT configured as Meta"
                print_result instruction "Option+F and Option+B shortcuts won't work for word navigation"
                print_result instruction "Configure in Terminal.app:"
                print_result info "Preferences → Profiles → Keyboard → ✓ Use Option as Meta key"
            end
        else
            print_result warn "Terminal.app preferences not found"
            print_result info "Expected: $terminal_prefs"
        end
    end

    if test "$check_performed" = false
        print_result info "Terminal: "(set -q TERM_PROGRAM; and echo $TERM_PROGRAM; or echo unknown)
        print_result info "For Option key shortcuts (word navigation) to work:"
        print_result info "• VS Code: Settings → terminal.integrated.macOptionIsMeta → true"
        print_result info "• iTerm2: Preferences → Profiles → Keys → Option Key → Esc+"
        print_result info "• Terminal.app: Preferences → Profiles → Keyboard → Use Option as Meta"
        print_result info "Run 'forge fish keyboard' for detailed keyboard shortcuts"
    end
else if test "$platform" = Linux
    if test "$TERM_PROGRAM" = vscode
        set check_performed true
        set -l vscode_settings "$HOME/.config/Code/User/settings.json"
        if test -f "$vscode_settings"
            if grep -q '"terminal.integrated.sendAltAsMetaKey"[[:space:]]*:[[:space:]]*true' "$vscode_settings" 2>/dev/null; or grep -q '"terminal.integrated.macOptionIsMeta"[[:space:]]*:[[:space:]]*true' "$vscode_settings" 2>/dev/null
                print_result pass "VS Code: Alt key configured as Meta"
            else
                print_result warn "VS Code: Alt key NOT configured as Meta"
                print_result instruction "Alt+F and Alt+B shortcuts won't work for word navigation"
                print_result instruction "Add to VS Code settings.json:"
                print_result code '"terminal.integrated.sendAltAsMetaKey": true'
                print_result instruction "Then reload VS Code: Ctrl+Shift+P → Reload Window"
            end
        else
            print_result warn "VS Code settings file not found"
            print_result info "Expected: $vscode_settings"
        end
    else if set -q GNOME_TERMINAL_SERVICE; or test "$COLORTERM" = gnome-terminal
        set check_performed true
        print_result pass "GNOME Terminal: Alt key typically works by default"
        print_result info "If Alt+F/B don't work, check: Preferences → Profile → Keyboard"
    else if test "$COLORTERM" = truecolor; and command -q konsole
        set check_performed true
        print_result pass "Konsole: Alt key typically works by default"
        print_result info "If Alt+F/B don't work, check: Settings → Edit Profile → Keyboard"
    else if set -q ALACRITTY_SOCKET; or test "$TERM" = alacritty
        set check_performed true
        print_result pass "Alacritty: Alt key typically works by default"
        print_result info "Config: ~/.config/alacritty/alacritty.toml"
    else if test "$TERM" = xterm; or test "$TERM" = xterm-256color
        set check_performed true
        set -l xresources "$HOME/.Xresources"
        if test -f "$xresources"
            if grep -q 'XTerm\*metaSendsEscape:[[:space:]]*true' "$xresources" 2>/dev/null; or grep -q 'XTerm\*eightBitInput:[[:space:]]*false' "$xresources" 2>/dev/null
                print_result pass "xterm: Meta key configured"
            else
                print_result warn "xterm: Meta key may not be configured"
                print_result instruction "Add to ~/.Xresources:"
                print_result code "XTerm*metaSendsEscape: true"
                print_result instruction "Then reload: xrdb ~/.Xresources"
            end
        else
            print_result info "xterm detected"
            print_result info "To enable Alt as Meta, add to ~/.Xresources:"
            print_result info "XTerm*metaSendsEscape: true"
        end
    end

    if test "$check_performed" = false
        print_result info "Terminal: "(set -q TERM_PROGRAM; and echo $TERM_PROGRAM; or echo $TERM)
        print_result info "For Alt key shortcuts (word navigation) to work:"
        print_result info "• VS Code: Settings → terminal.integrated.sendAltAsMetaKey → true"
        print_result info "• GNOME Terminal: Usually works by default"
        print_result info "• Konsole: Usually works by default"
        print_result info "• xterm: Add 'XTerm*metaSendsEscape: true' to ~/.Xresources"
        print_result info "Run 'forge fish keyboard' for detailed keyboard shortcuts"
    end
else
    print_result info "Keyboard check: Platform $platform - manual verification needed"
    print_result info "Ensure Alt/Meta key is configured for word navigation shortcuts"
end

# 9. Nerd Font support
print_section "Nerd Font"

set -l nerd_font_disabled false
if set -q NERD_FONT; and test -n "$NERD_FONT"
    if contains -- "$NERD_FONT" 1 true
        print_result pass "NERD_FONT: enabled"
    else
        print_result warn "NERD_FONT: disabled ($NERD_FONT)"
        print_result instruction "Enable Nerd Font by setting:"
        print_result code "set -Ux NERD_FONT 1"
        set nerd_font_disabled true
    end
else if set -q USE_NERD_FONT; and test -n "$USE_NERD_FONT"
    if contains -- "$USE_NERD_FONT" 1 true
        print_result pass "USE_NERD_FONT: enabled"
    else
        print_result warn "USE_NERD_FONT: disabled ($USE_NERD_FONT)"
        print_result instruction "Enable Nerd Font by setting:"
        print_result code "set -Ux NERD_FONT 1"
        set nerd_font_disabled true
    end
else
    print_result pass "Nerd Font: enabled (default)"
    print_result info "Forge will auto-detect based on terminal capabilities"
end

if test "$nerd_font_disabled" = false
    echo
    echo (__doctor_yellow "Visual Check [Manual Verification Required]")
    echo "   "(__doctor_bold "󱙺 FORGE 33.0k")" "(__doctor_cyan " tonic-1.0")
    echo
    echo "   Forge uses Nerd Fonts to enrich the CLI experience; can you see all the icons clearly without any overlap?"
    echo "   If you see boxes (□) or question marks (?), install a Nerd Font from:"
    echo "   "(__doctor_dim "https://www.nerdfonts.com/")
    echo
end

# Summary
echo
if test $__doctor_failed -eq 0; and test $__doctor_warnings -eq 0
    echo (__doctor_green $__doctor_pass)" "(__doctor_bold "All checks passed")" "(__doctor_dim "($__doctor_passed)")
    exit 0
else if test $__doctor_failed -eq 0
    echo (__doctor_yellow $__doctor_warn)" "(__doctor_bold "$__doctor_warnings warnings")" "(__doctor_dim "($__doctor_passed passed)")
    exit 0
else
    echo (__doctor_red $__doctor_fail)" "(__doctor_bold "$__doctor_failed failed")" "(__doctor_dim "($__doctor_warnings warnings, $__doctor_passed passed)")
    exit 1
end
