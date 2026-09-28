#!/bin/sh
# Warns when more than one tmux is on PATH, listing each in PATH order, so one
# built by hand or left by apt beside Homebrew's is noticed. It removes
# nothing, and always exits 0 so it never fails setup.
#
# TODO(undecided): where this lives. It is its own script beside
# check-corepack.sh, called by both setups; it could instead be inline in each
# setup/<os>/setup.sh.
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
