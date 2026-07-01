#!/bin/sh
DIR="${1:-$PWD}"
# The path may arrive as an OSC 7 payload (file://host/abs/path) when the shell
# reported its cwd via `printf '\e]7;...'` (tmux's pane_path). Strip the
# file://host prefix back to an absolute path. Emitted raw (not percent-encoded),
# so embedded spaces survive unchanged.
case "$DIR" in
  file://*) DIR="/${DIR#file://*/}" ;;
esac
ORIGIN="$DIR"
while [ "$DIR" != "/" ]; do
  if [ -e "$DIR/.git" ]; then
    basename "$DIR"
    exit 0
  fi
  DIR="$(dirname "$DIR")"
done
basename "$ORIGIN"
