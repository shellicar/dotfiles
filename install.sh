#!/bin/sh
# install.sh — make $HOME mirror the pointers under home/.
#
# Symlinks every file in home/common and home/<os> into the matching path
# under $HOME. Idempotent and re-runnable: already-correct links are left
# alone, our own symlinks get repointed, and a real file is never clobbered —
# it is moved to <file>.pre-dotfiles first.
#
# You run this; it changes $HOME.

set -eu

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
OS="${DOTFILES_OS:-$("$DOTFILES/get-os.sh")}"

link_tree() {
  src_root="$1"
  [ -d "$src_root" ] || return 0

  find "$src_root" -type f | while IFS= read -r src; do
    rel="${src#"$src_root"/}"
    dst="$HOME/$rel"

    # Already linked correctly -> skip.
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      continue
    fi

    mkdir -p "$(dirname "$dst")"

    if [ -L "$dst" ]; then
      ln -sfn "$src" "$dst"
      echo "repointed ~/$rel"
    elif [ -e "$dst" ]; then
      backup="$dst.pre-dotfiles"
      if [ -e "$backup" ]; then
        echo "skipped ~/$rel - real file present and backup already exists ($backup)" >&2
        continue
      fi
      mv "$dst" "$backup"
      ln -s "$src" "$dst"
      echo "linked ~/$rel (old file backed up to $backup)"
    else
      ln -s "$src" "$dst"
      echo "linked ~/$rel"
    fi
  done
}

echo "Installing dotfiles ($OS)..."
link_tree "$DOTFILES/home/common"
link_tree "$DOTFILES/home/$OS"
echo "Done."
