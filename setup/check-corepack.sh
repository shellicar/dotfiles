#!/bin/sh
# Reports each fnm Node version that has corepack's pnpm enabled, with the
# command that turns it off. It changes nothing, and always exits 0 so it never
# fails setup.
#
# Node ships no pnpm of its own. Corepack, once enabled, links one into that
# version's bin directory, and it answers ahead of the native pnpm in PNPM_BIN
# wherever that directory comes first on PATH. `fnm env` puts it first, and
# os/<os>.rc.sh puts PNPM_BIN back ahead of it in the dotfiles' interactive
# shells, so it is anything that loads fnm without that line after it that gets
# corepack's. So a pnpm symlink there is what this looks for.

DOTFILES=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../presentation.sh
. "$DOTFILES/presentation.sh"

for bin in "${FNM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/fnm}"/node-versions/*/installation/bin; do
  [ -L "$bin/pnpm" ] || continue
  version=${bin%/installation/bin}
  version=${version##*/}
  printf '%s\n' "$QUESTION ${YELLOW}${BOLD}Node $version has corepack's pnpm enabled.${RESET} To turn it off:"
  printf '    "%s/node" "%s/corepack" disable --install-directory "%s"\n' "$bin" "$bin" "$bin"
done

exit 0
