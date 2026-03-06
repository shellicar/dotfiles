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

detected_os=$(dirname "$0")/get-os.sh

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

echo "Installing GitVersion $tag ($platform) to $dest"

mkdir -p "$dest"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "Downloading $asset..."
gh release download "$tag" \
  --repo GitTools/GitVersion \
  --pattern "$asset" \
  --dir "$tmpdir"

echo "Extracting..."
tar -xzf "$tmpdir/$asset" -C "$dest"
chmod +x "$dest/gitversion"

echo "Installed: $dest/gitversion"
"$dest/gitversion" version
