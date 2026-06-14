#!/bin/sh
# User-private bins — prepended LAST so they take precedence over Homebrew etc.
# load.sh sources this at the very end of the env phase; its position is the rule.

[ -d "$HOME/bin" ] && PATH="$HOME/bin:$PATH"
[ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH"
export PATH
