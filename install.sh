#!/bin/sh
# install.sh — make $HOME mirror the pointers under home/.
#
# Links the contents of home/common, then on WSL home/linux, then home/<os>
# into the matching paths under $HOME. Files and ordinary directories are
# linked per-file, so a folder can also hold files it did not link;
# directories named in is_whole_dir() are symlinked whole — for project dirs where per-file linking would drag in
# node_modules and the like.
#
# Idempotent and re-runnable: already-correct links are left alone, our own
# symlinks get repointed, and a real path is never clobbered (it is moved to
# <name>.pre-dotfiles first).
#
# After linking, it reports what is left over and deletes none of it. It looks
# only in the folders it linked into on this run.
#
# You run this; it changes $HOME.

set -eu

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
. "$DOTFILES/resolve-os.sh"
OS="${DOTFILES_OS:-$("$DOTFILES/get-os.sh")}"
BASE_OS=$(resolve_os "$OS")
. "$DOTFILES/presentation.sh"

# Directories symlinked whole rather than file-by-file.
is_whole_dir() {
  case "$1" in
    .hammerspoon) return 0 ;;
    .config/git/hooks) return 0 ;;
    *) return 1 ;;
  esac
}

# Folders under $HOME that hold only what is linked from here.
is_own_dir() {
  case "$1" in
    bin|lib) return 0 ;;
    *) return 1 ;;
  esac
}

# One path per line, with a newline either side.
NL='
'
linked_paths=$NL
skipped_paths=$NL
linked_dirs=$NL
note_linked() {
  linked_paths="$linked_paths$1$NL"
}
note_skipped() {
  skipped_paths="$skipped_paths$1$NL"
}
note_dir() {
  note_dir=$(dirname "$1")
  case "$linked_dirs" in
    *"$NL$note_dir$NL"*) ;;
    *) linked_dirs="$linked_dirs$note_dir$NL" ;;
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

  # Noted before the early returns below, so a re-run reports the same folders.
  note_dir "$dst"

  # Already linked correctly -> nothing to do.
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    note_linked "$dst"
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
      note_skipped "$dst"
      return 0
    fi
    mv "$dst" "$backup"
    ln -s "$src" "$dst"
    echo "linked ~/${dst#"$HOME"/} (existing moved to $backup)"
  else
    ln -s "$src" "$dst"
    echo "linked ~/${dst#"$HOME"/}"
  fi
  note_linked "$dst"
}

# Recurses so a whole-dir entry nested below the tree root is still found.
link_dir() {
  for src in "$1"/* "$1"/.[!.]*; do
    [ -e "$src" ] || continue
    rel="${src#"$src_root"/}"
    # Skips what the overlay also has, except an ordinary directory in both,
    # which is descended into.
    if [ -n "$overlay_root" ] && [ -e "$overlay_root/$rel" ]; then
      if ! { [ -d "$src" ] && [ -d "$overlay_root/$rel" ] && ! is_whole_dir "$rel"; }; then
        continue
      fi
    fi

    if [ -d "$src" ] && is_whole_dir "$rel"; then
      link_one "$src" "$HOME/$rel"
    elif [ -d "$src" ]; then
      link_dir "$src"
    else
      link_one "$src" "$HOME/$rel"
    fi
  done
  # Deliberate: an empty directory would otherwise end on the failed -e test.
  return 0
}

link_tree() {
  src_root="$1"
  # Optional overlay root: a file or whole-dir entry that also exists under it
  # is left for that tier to link, so a base tier and its overlay don't fight
  # over the same destination on every run.
  overlay_root="${2:-}"
  [ -d "$src_root" ] || return 0
  link_dir "$src_root"
}

# The command that deletes $1. The path is single-quoted: in double quotes, a
# name holding $(…), backticks or $VAR would run or expand when pasted.
delete_command() {
  quoted=$(printf '%s\n' "$1" | sed "s/'/'\\\\''/g")
  if [ -d "$1" ] && [ ! -L "$1" ]; then
    printf "    rm -r '%s'\n" "$quoted"
  else
    printf "    rm '%s'\n" "$quoted"
  fi
}

# Looks only at the folders themselves, not below them: a whole-dir link leads
# into the repo.
report_leftovers() {
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    for entry in "$dir"/* "$dir"/.[!.]*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      rel=${entry#"$HOME"/}
      if [ -L "$entry" ] && [ ! -e "$entry" ]; then
        printf '%s\n' "$WARN${YELLOW}${BOLD}~/$rel is a link to $(readlink "$entry"), which does not exist.${RESET} To delete it:"
        delete_command "$entry"
        continue
      fi
      case "$skipped_paths" in *"$NL$entry$NL"*)
        printf '%s\n' "$WARN${YELLOW}${BOLD}install.sh could not link ~/$rel because it and its backup ~/$rel.pre-dotfiles are both there.${RESET} Move one of them aside."
        continue ;;
      esac
      case "$entry" in
        *.pre-dotfiles)
          # Already reported with the path it backs up.
          case "$skipped_paths" in *"$NL${entry%.pre-dotfiles}$NL"*) continue ;; esac
          printf '%s\n' "$QUESTION ${YELLOW}${BOLD}~/$rel is a backup of ~/${rel%.pre-dotfiles}.${RESET} To delete it:"
          delete_command "$entry"
          continue ;;
      esac
      is_own_dir "${dir#"$HOME"/}" || continue
      case "$linked_paths" in *"$NL$entry$NL"*) continue ;; esac
      case "$linked_dirs" in *"$NL$entry$NL"*) continue ;; esac
      printf '%s\n' "$QUESTION ${YELLOW}${BOLD}~/$rel is not linked from the dotfiles.${RESET} To delete it:"
      delete_command "$entry"
    done
  done <<EOF
$linked_dirs
EOF
  return 0
}

echo "Installing dotfiles ($OS)..."
link_tree "$DOTFILES/home/common"
# BASE_OS is a family base (e.g. linux for WSL). Link it first so the
# OS-specific tree below can still override individual files in it.
[ "$BASE_OS" != "$OS" ] && link_tree "$DOTFILES/home/$BASE_OS" "$DOTFILES/home/$OS"
link_tree "$DOTFILES/home/$OS"
report_leftovers
echo "Done."
