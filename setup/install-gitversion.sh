#!/bin/sh
set -e

LATEST_5="5.12.0"
LATEST_6="6.6.0"

usage() {
  echo "Usage: $0 <version>"
  echo ""
  echo "Versions:"
  echo "  5    Install GitVersion $LATEST_5"
  echo "  6    Install GitVersion $LATEST_6"
  echo ""
  echo "Installs to ~/.gitversion/<major>/gitversion"
  exit 1
}

if [ $# -ne 1 ]; then
  usage
fi

case "$1" in
  5) tag="$LATEST_5" ;;
  6) tag="$LATEST_6" ;;
  *) usage ;;
esac

major="$1"

detected_os=$(dirname "$0")/../get-os.sh

case $($detected_os) in
  wsl|linux)
    arch=$(uname -m)
    case "$arch" in
      x86_64)  platform="linux-x64" ;;
      aarch64) platform="linux-arm64" ;;
      *) echo "Error: Unsupported architecture: $arch" >&2; exit 1 ;;
    esac
    ;;
  macos)
    arch=$(uname -m)
    case "$arch" in
      x86_64) platform="osx-x64" ;;
      arm64)  platform="osx-arm64" ;;
      *) echo "Error: Unsupported architecture: $arch" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "Error: Unsupported OS" >&2
    exit 1
    ;;
esac

asset="gitversion-${platform}-${tag}.tar.gz"
dest="$HOME/.gitversion/$major"

# A setup re-run is expected to bring things up to date, which is what brew
# bundle and apt-get install already do, so this compares against the wanted
# version rather than mere presence. Bumping LATEST_5 or LATEST_6 would
# otherwise never take effect on a machine that already had something.
# gitversion reports 6.6.0+Branch.main.Sha.abc123; the build metadata after
# the + varies per build and is not part of the release version.
have=$("$dest/gitversion" version 2>/dev/null) || have=''
if [ "${have%%+*}" = "$tag" ]; then
  echo "GitVersion $tag already installed at $dest"
  exit 0
fi

echo "Installing GitVersion $tag ($platform) to $dest"

mkdir -p "$dest"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# The public release URL needs no authentication, so this does not drag in the
# GitHub CLI, which is in neither setup/macos/Brewfile nor setup/linux/packages
# and is not a one-line apt install on older Debian. -f is what makes a 404 a
# failed download rather than an error page saved as a tarball.
url="https://github.com/GitTools/GitVersion/releases/download/$tag/$asset"

echo "Downloading $asset..."
curl -fsSL -o "$tmpdir/$asset" "$url"

echo "Extracting..."
tar -xzf "$tmpdir/$asset" -C "$dest"
chmod +x "$dest/gitversion"

echo "Installed: $dest/gitversion"
"$dest/gitversion" version
