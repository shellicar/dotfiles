#!/bin/sh
# Build GnuPG from source with the local scdaemon patch, and stage the result
# into the dotfiles tree so the other machines get it from the clone.
#
# GnuPG is not in the Brewfile: a patched component and a package manager that
# always installs the latest version cannot coexist, since a fresh `brew install`
# on another machine would pair a new gpg-agent with the vendored scdaemon.
# Owning the whole install keeps every component on one version.
#
# The patch stops scdaemon discarding a verified CHV after a touch timeout. See
# docs/yubikey.md.
#
# Dry run by default. --apply builds and stages.
set -e

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
SRC="${SRC:-$HOME/repos/gpg/gnupg}"
PREFIX="$HOME/.local/gnupg"
STAGE="$DOTFILES/home/macos/.local/gnupg"
PATCH="$DOTFILES/patches/gnupg-keep-chv-on-timeout.patch"
VERSION_FILE="$DOTFILES/patches/gnupg.version"
REMOTE=git://git.gnupg.org/gnupg.git

apply=0
[ "${1:-}" = "--apply" ] && apply=1

[ -f "$VERSION_FILE" ] || { echo "missing $VERSION_FILE" >&2; exit 64; }
[ -f "$PATCH" ] || { echo "missing $PATCH" >&2; exit 64; }
tag=$(cat "$VERSION_FILE")

echo "Plan:"
echo "  tag:     $tag"
echo "  source:  $SRC"
echo "  prefix:  $PREFIX"
echo "  stage:   $STAGE"
echo ""
[ -d "$SRC/.git" ] && echo "  1. fetch $REMOTE" || echo "  1. clone $REMOTE into $SRC"
echo "  2. check out $tag, discarding local changes in scd/"
echo "  3. apply $(basename "$PATCH")"
echo "  4. autogen, configure --prefix=$PREFIX, make"
echo "  5. make install into $PREFIX"
echo "  6. copy the install into the dotfiles tree"
echo ""

if [ "$apply" -eq 0 ]; then
  echo "Dry run. Re-run with --apply to build."
  exit 0
fi

if [ -d "$SRC/.git" ]; then
  git -C "$SRC" fetch --tags "$REMOTE"
else
  mkdir -p "$(dirname "$SRC")"
  git clone "$REMOTE" "$SRC"
fi

# A previous run leaves the patch applied, so start from the tag every time.
git -C "$SRC" switch --detach "$tag"
git -C "$SRC" checkout -- scd/
git -C "$SRC" apply "$PATCH"

cd "$SRC"
[ -f configure ] || ./autogen.sh

# --disable-ldap: the dirmngr LDAP test target compiles without the gnutls
# include path its own build needs, so the tree does not build with it on. LDAP
# keyservers are not used here.
./configure --prefix="$PREFIX" --disable-nls --disable-ldap

# doc/ needs ImageMagick and texinfo to generate diagrams and info files that
# are discarded anyway, so only the subdirectories producing binaries are built.
subdirs="m4 common regexp kbx g10 sm agent scd dirmngr tools"
make -j"$(sysctl -n hw.ncpu)" SUBDIRS="$subdirs"
make install SUBDIRS="$subdirs"

# Copied over the top rather than replaced. A version bump can leave files here
# that the new install no longer produces, so clear the staged tree by hand when
# the tag changes.
mkdir -p "$STAGE"
cp -R "$PREFIX/." "$STAGE/"

echo ""
echo "Built $tag and staged into $STAGE"
echo "Commit the result; git-lfs handles the binaries."
