#!/bin/sh
set -e

# The Go toolchain. Ubuntu 24.04's apt has 1.22, which
# is older than repos pinning `go 1.24.x` in go.mod, so apt is not an option.
#
# Only one version is installed, deliberately. Since Go 1.21 the `go` command
# reads the `go`/`toolchain` lines in a module's go.mod and downloads the
# matching toolchain on demand (GOTOOLCHAIN=auto, the default), so a project
# needing something newer than GO_VERSION fetches it itself. There is nothing
# here for a version manager to do.
GO_VERSION="1.24.5"

detected_os=$(dirname "$0")/../get-os.sh

case $($detected_os) in
  wsl|linux) goos="linux" ;;
  macos)     goos="darwin" ;;
  *) echo "Error: Unsupported OS" >&2; exit 1 ;;
esac

arch=$(uname -m)
case "$arch" in
  x86_64)         goarch="amd64" ;;
  aarch64|arm64)  goarch="arm64" ;;
  *) echo "Error: Unsupported architecture: $arch" >&2; exit 1 ;;
esac

platform="${goos}-${goarch}"
asset="go${GO_VERSION}.${platform}.tar.gz"
dest="$HOME/.go"

# As in install-gitversion.sh, this compares against the wanted version rather
# than mere presence, so bumping GO_VERSION takes effect on a machine that
# already has an older Go. `go version` prints "go version go1.24.5 linux/amd64".
have=$("$dest/bin/go" version 2>/dev/null | awk '{print $3}') || have=''
if [ "$have" = "go${GO_VERSION}" ]; then
  echo "Go ${GO_VERSION} already installed at $dest"
  exit 0
fi

echo "Installing Go ${GO_VERSION} (${platform}) to $dest"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

url="https://go.dev/dl/${asset}"

echo "Downloading ${asset}..."
curl -fsSL -o "$tmpdir/$asset" "$url"

echo "Extracting..."
# Upstream's instructions untar into a directory that becomes GOROOT, and are
# emphatic about removing the old one first rather than unpacking over it.
# --strip-components=1 drops the tarball's own leading go/ so GOROOT is
# ~/.go: unpacking it bare into $HOME would land on ~/go, which is GOPATH.
rm -rf "$dest"
mkdir -p "$dest"
tar -xzf "$tmpdir/$asset" -C "$dest" --strip-components=1

echo "Installed: $dest/bin/go"
"$dest/bin/go" version
