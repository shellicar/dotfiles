#!/bin/sh
# install.sh — make $HOME mirror the pointers under home/.
#
# Links the contents of home/common, then on WSL home/linux, then home/<os>
# into the matching paths under $HOME. Files and ordinary directories are
# linked per-file, so a folder can also hold files it did not link (those in
# ~/bin and ~/lib are reported, below); directories named in is_whole_dir()
# are symlinked whole — for project dirs where per-file linking would drag in
# node_modules and the like.
#
# Idempotent and re-runnable: already-correct links are left alone, our own
# symlinks get repointed, and a real path is never clobbered (it is moved to
# <name>.pre-dotfiles first).
#
# Once linked, it reports what is left over, and changes none of it: a dead
# link in any folder it links into, a <name>.pre-dotfiles backup there, and,
# in the folders named in is_own_dir(), anything it did not link. Each comes
# with the command that deletes it. A leftover does not change the exit status.
# Only the folders it links into on this run are looked at, so a dead link in a
# folder the repo no longer has anything for is not reported.
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

# Folders under $HOME that exist only to hold what is linked from here, so
# anything else in them is reported. Every other folder is shared with other
# programs, and only a dead link is reported there.
is_own_dir() {
  case "$1" in
    bin|lib) return 0 ;;
    *) return 1 ;;
  esac
}

# Every destination install.sh has linked, and every folder it links into, one
# per line with a newline either side, for the leftover report.
NL='
'
linked_paths=$NL
linked_dirs=$NL
note_linked() {
  linked_paths="$linked_paths$1$NL"
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

  # The folder is noted before the early returns below, so a re-run reports the
  # same folders. The path is noted only where the link exists: one skipped
  # below is not install.sh's, and is reported like anything else it did not link.
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
    # An ordinary directory in both tiers is merged: descend into it, and this
    # test then skips only the entries inside it that the overlay also has.
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
  # over the same destination on every run. An ordinary directory in both is
  # merged, and the overlay's copy wins only for the files both have.
  overlay_root="${2:-}"
  [ -d "$src_root" ] || return 0
  link_dir "$src_root"
}

# The command that deletes $1. A link to a directory is removed as a link.
# The path is single-quoted, each ' in it written as '\'': inside double quotes,
# a name holding $(…), backticks or $VAR runs or expands when the command is
# pasted, and a crafted name can make it delete a different path.
delete_command() {
  quoted=$(printf '%s\n' "$1" | sed "s/'/'\\\\''/g")
  if [ -d "$1" ] && [ ! -L "$1" ]; then
    printf "    rm -r '%s'\n" "$quoted"
  else
    printf "    rm '%s'\n" "$quoted"
  fi
}

# Looks only at the folders themselves, not below them: a whole-dir link is
# the repo, and anything deeper was never linked into.
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
      case "$entry" in
        *.pre-dotfiles)
          printf '%s\n' "$QUESTION ${YELLOW}${BOLD}~/$rel is a backup install.sh made of ~/${rel%.pre-dotfiles}.${RESET} To delete it:"
          delete_command "$entry"
          continue ;;
      esac
      is_own_dir "${dir#"$HOME"/}" || continue
      case "$linked_paths" in *"$NL$entry$NL"*) continue ;; esac
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
