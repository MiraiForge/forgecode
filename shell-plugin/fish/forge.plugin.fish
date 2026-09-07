#!/usr/bin/env fish

# Documentation in [README.md](../README.md)
#
# Development entry point that sources the modular fish plugin from a checkout.
# `forge fish plugin` embeds the same lib/ files, appends command stubs and
# completions, and is what `forge fish setup` installs.

set -l __forge_dir (dirname (status filename))

# Configuration variables
source $__forge_dir/lib/config.fish

# Core utilities (includes logging)
source $__forge_dir/lib/helpers.fish

# Terminal context capture (preexec/postexec hooks, OSC 133)
source $__forge_dir/lib/context.fish

# Completion widget
source $__forge_dir/lib/completion.fish

# Action handlers
for __forge_file in $__forge_dir/lib/actions/*.fish
    source $__forge_file
end

# Main dispatcher and Enter widget
source $__forge_dir/lib/dispatcher.fish

# Key bindings
source $__forge_dir/lib/bindings.fish

__forge_init
set -g _FORGE_PLUGIN_LOADED (date +%s)
