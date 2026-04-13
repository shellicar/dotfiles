#!/bin/bash
#CURRENT="$(tmux display-message -p '#{pane_current_path}')"
CURRENT="$(tmux display-message -p '#{session_path}')"
CACHE="/tmp/.tmux-vscode-last"
LAST="$(cat "$CACHE" 2>/dev/null)"
if [ "$CURRENT" != "$LAST" ]; then
  echo "$CURRENT" > "$CACHE"
  TMUX= code --reuse-window "$CURRENT"
  #open -a "Visual Studio Code" "$CURRENT"
fi
