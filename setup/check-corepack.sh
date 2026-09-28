#!/bin/sh
# Reports each fnm Node version that has corepack's pnpm enabled, with the
# command that turns it off. It changes nothing.
#
# A pnpm symlink in a Node version's bin is corepack's, and it can run ahead of
# the native pnpm.

DOTFILES=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../presentation.sh
. "$DOTFILES/presentation.sh"

for bin in "${FNM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/fnm}"/node-versions/*/installation/bin; do
  [ -L "$bin/pnpm" ] || continue
  version=${bin%/installation/bin}
  version=${version##*/}
  printf '%s\n' "$QUESTION ${YELLOW}${BOLD}Node $version has corepack's pnpm enabled.${RESET} To turn it off:"
  # Single-quoted: in double quotes, pasting it would run a $(…) or backticks
  # in a directory name.
  quoted=$(printf '%s' "$bin" | sed "s/'/'\\\\''/g")
  printf "    '%s/node' '%s/corepack' disable --install-directory '%s'\n" "$quoted" "$quoted" "$quoted"
done

exit 0
