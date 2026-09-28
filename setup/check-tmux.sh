#!/bin/sh
# Warns when more than one tmux is on PATH, listing each in PATH order. It
# removes nothing.
#
# A directory reached by two PATH entries counts once: Ubuntu links /bin to
# /usr/bin and has both on PATH, so one apt tmux would otherwise read as two.

DOTFILES=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../presentation.sh
. "$DOTFILES/presentation.sh"

found=
count=0
seen=:
rest=$PATH
while [ -n "$rest" ]; do
  case "$rest" in
    *:*) dir=${rest%%:*}; rest=${rest#*:} ;;
    *)   dir=$rest; rest= ;;
  esac
  if [ -z "$dir" ] || [ ! -f "$dir/tmux" ] || [ ! -x "$dir/tmux" ]; then
    continue
  fi
  real=$(cd "$dir" 2>/dev/null && pwd -P) || continue
  case "$seen" in *":$real:"*) continue ;; esac
  seen="$seen$real:"
  count=$((count + 1))
  found="$found    $dir/tmux
"
done

if [ "$count" -gt 1 ]; then
  printf '%s\n' "$WARN${YELLOW}${BOLD}$count tmux binaries are on PATH; the first one listed is the one that runs.${RESET}"
  printf '%s' "$found"
fi

exit 0
