#!/bin/sh
# resolve_os: collapses an OS name for directory-selection purposes. WSL is
# Debian/Ubuntu underneath, so it maps to "linux" here, used by scripts that
# pick a setup/home directory by OS (setup.sh, install.sh).
#
# Callers that need to tell WSL and native Linux apart (load.sh,
# install-gitversion.sh, .vscode/sync.mjs) want the raw get-os.sh/DOTFILES_OS
# value instead. Do not route those through this.
resolve_os() {
  case "$1" in
    wsl) echo linux ;;
    *) echo "$1" ;;
  esac
}
