#!/bin/sh
PANE_PATH="$(tmux display-message -p '#{pane_current_path}')"

# Find git root — skip if not in a repo
DIR="$PANE_PATH"
while [ "$DIR" != "/" ]; do
  if [ -e "$DIR/.git" ]; then
    break
  fi
  DIR="$(dirname "$DIR")"
done

# No repo found, do nothing
[ "$DIR" = "/" ] && exit 0

CACHE="/tmp/.tmux-vscode-last"
LAST="$(cat "$CACHE" 2>/dev/null)"
if [ "$DIR" != "$LAST" ]; then
  echo "$DIR" > "$CACHE"
  osascript -e 'tell application "Visual Studio Code" to open POSIX file "'"$DIR"'"'
fi

