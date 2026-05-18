#!/bin/sh
exec >> /tmp/tmux-vscode.log 2>&1
#set -x
PANE_PATH="${1:-$(tmux display-message -p '#{pane_current_path}')}"

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

osascript -e 'tell application "Visual Studio Code" to open POSIX file "'"$DIR"'"' >/dev/null
hs -c 'local w = hs.application.get("Code"); if w then local win = w:mainWindow(); if win then win:moveToUnit(hs.geometry.rect(0.5, 0, 0.5, 1)) end end'
