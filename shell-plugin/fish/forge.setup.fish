# !! This file is managed by 'forge fish setup' !!
# !! Do not edit manually - changes will be overwritten !!
# Put your own settings in ~/.config/fish/config.fish, which loads after this file.

# The plugin and theme only make sense in an interactive shell
status is-interactive; or exit

# Honour FORGE_BIN, and stay quiet when forge is not installed (run
# `forge fish doctor` to diagnose)
set -l __forge_bin forge
if set -q FORGE_BIN; and test -n "$FORGE_BIN"
    set __forge_bin $FORGE_BIN
end
command -q $__forge_bin; or exit

# Load forge shell plugin (commands, completions, keybindings) if not already
# loaded. Functions are checked rather than the _FORGE_*_LOADED variables so
# a value exported by a parent shell cannot suppress loading.
if not functions -q __forge_accept_line
    $__forge_bin fish plugin | source
end

# Load forge shell theme (right prompt with AI context) if not already loaded
if not functions -q __forge_prompt_info
    $__forge_bin fish theme | source
end
