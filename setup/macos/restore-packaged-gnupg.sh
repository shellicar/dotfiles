#!/bin/sh
# Move this machine off the vendored GnuPG and onto the packaged one.
#
# Per machine. The counterpart to uninstall-gnupg.sh, which does the repo side
# once. Run this after pulling that deletion, because the symlinks it clears are
# the ones that deletion leaves dangling.
#
# It removes any symlink pointing at a gone file under home/macos/. A name list
# would miss the ones left by earlier builds that staged binaries this repo no
# longer carries, and there are six of those. ~/.local/gnupg/libexec was linked
# as a whole directory rather than file by file, so it comes out as one link.
#
# A link that still resolves is one install.sh is maintaining and is left alone,
# which is why this finds the orphans now and the rest only once the deletion
# has reached main.
#
# Dry run by default. --apply does it.
set -e

SCDAEMON_CONF="$HOME/.gnupg/scdaemon.conf"

STAGE="$HOME/dotfiles/home/macos/"

apply=0
[ "${1:-}" = "--apply" ] && apply=1

command -v brew >/dev/null 2>&1 || { echo "ERROR: brew not found" >&2; exit 64; }

orphan() {
  [ -L "$1" ] || return 1
  [ -e "$1" ] && return 1
  case "$(readlink "$1")" in
    "$STAGE"*) return 0 ;;
  esac
  return 1
}

LINKS=""
orphan "$HOME/.local/gnupg/libexec" && LINKS="$LINKS $HOME/.local/gnupg/libexec"
for p in "$HOME/bin"/*; do
  orphan "$p" && LINKS="$LINKS $p"
done

chv=0
if [ -f "$SCDAEMON_CONF" ] && grep -q 'keep-chv-on-timeout' "$SCDAEMON_CONF"; then
  chv=1
fi

echo "Plan:"
echo "  1. brew install gnupg"
if [ -n "$LINKS" ]; then
  echo "  2. remove these dangling symlinks:"
  for p in $LINKS; do
    echo "       $p"
  done
else
  echo "  2. no dangling symlinks, nothing to remove"
fi
if [ "$chv" -eq 1 ]; then
  echo "  3. remove keep-chv-on-timeout from $SCDAEMON_CONF"
else
  echo "  3. keep-chv-on-timeout is not set, nothing to remove"
fi
echo "  4. stop gpg-agent and scdaemon, so the packaged ones start next time"
echo ""

if [ "$apply" -eq 0 ]; then
  echo "Dry run. Re-run with --apply to do it."
  exit 0
fi

echo "1. brew install gnupg"
brew install gnupg

echo "2. symlinks"
for p in $LINKS; do
  rm "$p"
  echo "   removed $p"
done

echo "3. scdaemon.conf"
if [ "$chv" -eq 1 ]; then
  # grep -v exits 1 when it produces no lines, which is the case where that was
  # the only line in the file.
  grep -v 'keep-chv-on-timeout' "$SCDAEMON_CONF" > "$SCDAEMON_CONF.new" || true
  mv "$SCDAEMON_CONF.new" "$SCDAEMON_CONF"
  echo "   removed keep-chv-on-timeout"
fi

echo "4. stopping the running agents"
gpgconf --kill all || true

echo ""
echo "Now using: $(command -v gpg)"
gpg --version | head -1
