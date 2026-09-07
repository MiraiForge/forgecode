#!/usr/bin/env fish

# Key bindings for the forge fish plugin
#
# Bindings are created at the user level, so they take precedence over fish's
# preset bindings and survive `fish_vi_key_bindings` / `fish_default_key_bindings`,
# which only reset the preset level. Both the emacs (`default`) and vi insert
# modes get the bindings; `default` doubles as vi normal mode.

function __forge_apply_keybindings --description 'Bind Enter and Tab to the Forge widgets'
    for mode in default insert
        if test "$_FORGE_FISH_MAJOR" -ge 4
            # fish 4 named keys; with modern keyboard protocols Enter and
            # ctrl-m are distinct, so bind every variant the preset binds.
            bind -M $mode enter __forge_accept_line
            bind -M $mode ctrl-j __forge_accept_line
            bind -M $mode ctrl-m __forge_accept_line
            bind -M $mode ctrl-enter __forge_accept_line
            bind -M $mode tab __forge_complete
        else
            bind -M $mode \r __forge_accept_line
            bind -M $mode \n __forge_accept_line
            bind -M $mode \t __forge_complete
        end
    end
end

# Entry point called once all plugin files are defined
function __forge_init --description 'Apply Forge key bindings'
    __forge_apply_keybindings
end
