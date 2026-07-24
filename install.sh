#!/bin/sh
# install.sh — make $HOME mirror the pointers under home/.
#
# Links the contents of home/common and home/<os> into the matching paths
# under $HOME. Files and ordinary directories are linked per-file (so e.g.
# ~/bin can also hold unmanaged files); directories named in is_whole_dir()
# are symlinked whole — for project dirs where per-file linking would drag in
# node_modules and the like.
#
# Idempotent and re-runnable: already-correct links are left alone, our own
# symlinks get repointed, and a real path is never clobbered (it is moved to
# <name>.pre-dotfiles first).
#
# You run this; it changes $HOME.

set -eu

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
. "$DOTFILES/resolve-os.sh"
OS="${DOTFILES_OS:-$("$DOTFILES/get-os.sh")}"
BASE_OS=$(resolve_os "$OS")

# Directories symlinked whole rather than file-by-file.
is_whole_dir() {
  case "$1" in
    .hammerspoon) return 0 ;;
    *) return 1 ;;
  esac
}

# True if any parent directory of $1 (below $HOME) is a symlink. Writing into
# it would land inside the symlink's target (e.g. back in the repo), not $HOME.
has_symlink_parent() {
  p=$(dirname "$1")
  while [ "$p" != "$HOME" ] && [ "$p" != "/" ] && [ -n "$p" ]; do
    [ -L "$p" ] && return 0
    p=$(dirname "$p")
  done
  return 1
}

link_one() {
  src="$1"
  dst="$2"

  # Refuse to write through a symlinked directory, or we would mangle its target.
  if has_symlink_parent "$dst"; then
    echo "refusing ~/${dst#"$HOME"/}: a parent dir is a symlink, remove it and re-run" >&2
    return 0
  fi

  # Already linked correctly -> nothing to do.
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$dst")"

  if [ -L "$dst" ]; then
    ln -sfn "$src" "$dst"
    echo "repointed ~/${dst#"$HOME"/}"
  elif [ -e "$dst" ]; then
    backup="$dst.pre-dotfiles"
    if [ -e "$backup" ]; then
      echo "skipped ~/${dst#"$HOME"/} - present and backup already exists ($backup)" >&2
      return 0
    fi
    mv "$dst" "$backup"
    ln -s "$src" "$dst"
    echo "linked ~/${dst#"$HOME"/} (existing moved to $backup)"
  else
    ln -s "$src" "$dst"
    echo "linked ~/${dst#"$HOME"/}"
  fi
}

link_tree() {
  src_root="$1"
  # Optional overlay root: paths that also exist under it are left for that
  # tier to link, so a base tier and its overlay don't fight over the same
  # destination on every run.
  overlay_root="${2:-}"
  [ -d "$src_root" ] || return 0

  # Walk immediate entries (incl. dotfiles). Whole-dir entries get one symlink;
  # everything else is linked per-file.
  for src in "$src_root"/* "$src_root"/.[!.]*; do
    [ -e "$src" ] || continue
    rel="${src#"$src_root"/}"
    [ -n "$overlay_root" ] && [ -e "$overlay_root/$rel" ] && continue

    if [ -d "$src" ] && is_whole_dir "$rel"; then
      link_one "$src" "$HOME/$rel"
    elif [ -d "$src" ]; then
      find "$src" -type f | while IFS= read -r f; do
        subrel="${f#"$src_root"/}"
        [ -n "$overlay_root" ] && [ -e "$overlay_root/$subrel" ] && continue
        link_one "$f" "$HOME/$subrel"
      done
    else
      link_one "$src" "$HOME/$rel"
    fi
  done
}

echo "Installing dotfiles ($OS)..."
link_tree "$DOTFILES/home/common"
# BASE_OS is a family base (e.g. linux for WSL). Link it first so the
# OS-specific tree below can still override individual files in it.
[ "$BASE_OS" != "$OS" ] && link_tree "$DOTFILES/home/$BASE_OS" "$DOTFILES/home/$OS"
link_tree "$DOTFILES/home/$OS"
echo "Done."
