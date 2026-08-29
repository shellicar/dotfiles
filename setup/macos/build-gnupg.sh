#!/bin/sh
# Build GnuPG from source with the local scdaemon patch and copy the binaries
# into the dotfiles tree.
#
# GnuPG is not in the Brewfile: a patched component and a package manager that
# always installs the latest version cannot coexist, so the whole install is
# owned here and every component stays on one version.
#
# The patch stops scdaemon discarding a verified CHV after a touch timeout. See
# docs/yubikey.md.
#
# Dry run by default. --apply builds.
set -e

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
SRC="${SRC:-$HOME/repos/gpg/gnupg}"

# GnuPG bakes its bindir and libexecdir in at configure time, so they name where
# install.sh will link them: bin/ per file into ~/bin, and .local/gnupg as a
# whole directory. DESTDIR then stages the install elsewhere without changing
# those baked paths, so the build never writes into the repo.
PREFIX="$HOME/.local/gnupg"
BINDIR="$HOME/bin"
BUILD_ROOT="${BUILD_ROOT:-/tmp/gnupg-build}"

STAGE_BIN="$DOTFILES/home/macos/bin"
STAGE_LIBEXEC="$DOTFILES/home/macos/.local/gnupg/libexec"

# Only these are copied in. The install also writes sbin, share and its own
# README, none of which are wanted here.
BINARIES="dirmngr dirmngr-client gpg gpg-agent gpg-card gpg-connect-agent gpgconf gpgsm gpgsplit gpgtar gpgv kbxutil"
LIBEXEC="gpg-check-pattern gpg-preset-passphrase gpg-protect-tool keyboxd scdaemon"

PATCH="$DOTFILES/patches/gnupg-keep-chv-on-timeout.patch"
VERSION_FILE="$DOTFILES/patches/gnupg.version"
REMOTE=git://git.gnupg.org/gnupg.git

apply=0
[ "${1:-}" = "--apply" ] && apply=1

[ -f "$VERSION_FILE" ] || { echo "missing $VERSION_FILE" >&2; exit 64; }
[ -f "$PATCH" ] || { echo "missing $PATCH" >&2; exit 64; }
tag=$(cat "$VERSION_FILE")

echo "Plan:"
echo "  tag:        $tag"
echo "  source:     $SRC"
echo "  build root: $BUILD_ROOT"
echo "  stage:      $STAGE_BIN"
echo "              $STAGE_LIBEXEC"
echo ""
[ -d "$SRC/.git" ] && echo "  1. fetch $REMOTE" || echo "  1. clone $REMOTE into $SRC"
echo "  2. check out $tag, discarding local changes in scd/"
echo "  3. apply $(basename "$PATCH")"
echo "  4. autogen, configure, make"
echo "  5. make install into $BUILD_ROOT"
echo "  6. copy $(echo "$BINARIES" | wc -w | tr -d ' ') binaries and $(echo "$LIBEXEC" | wc -w | tr -d ' ') helpers into the dotfiles tree"
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
./configure --prefix="$PREFIX" --bindir="$BINDIR" --disable-nls --disable-ldap

# doc/ needs ImageMagick and texinfo to generate diagrams and info files that
# are not wanted, so only the subdirectories producing binaries are built.
subdirs="m4 common regexp kbx g10 sm agent scd dirmngr tools"
make -j"$(sysctl -n hw.ncpu)" SUBDIRS="$subdirs"
make install SUBDIRS="$subdirs" DESTDIR="$BUILD_ROOT"

mkdir -p "$STAGE_BIN" "$STAGE_LIBEXEC"
for f in $BINARIES; do
  cp "$BUILD_ROOT$BINDIR/$f" "$STAGE_BIN/$f"
done
for f in $LIBEXEC; do
  cp "$BUILD_ROOT$PREFIX/libexec/$f" "$STAGE_LIBEXEC/$f"
done

echo ""
echo "Built $tag and copied into the dotfiles tree."
echo "Run ./install.sh to link it, then commit; git-lfs handles the binaries."
