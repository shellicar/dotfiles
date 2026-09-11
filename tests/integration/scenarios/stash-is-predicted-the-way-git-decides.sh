#!/bin/sh
# Whether a stash is needed is worked out before anything is attempted, from
# what git is about to write against what is sitting in the worktree. That claim
# is only worth anything if it matches what git really does, and git is the only
# thing that can say. So each case asks the predicate, then attempts the
# operation for real and compares the two.
#
# This is why the rules are what they are, written down where they can be
# checked rather than asserted in a comment:
#
#   rebase refuses on ANY tracked change, whatever the change is
#   rebase allows an untracked file the incoming commits never create
#   everything refuses an untracked file the incoming commits DO create
#   fast-forward allows an unrelated modification, even a staged one
#
# Each case gets its own worktree, so nothing has to be undone between them.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

# u.txt is the file nothing incoming ever touches. n.txt is the file main
# creates, which is what an untracked copy can collide with.
commit U u.txt
git push -q origin main
base=$(git rev-parse HEAD)

commit B a.txt
printf 'new\n' > n.txt
git add n.txt
git commit -qm N
git push -q origin main
git fetch -q origin

# The library is sourced rather than run through a command, because the subject
# is one predicate and the comparison is against git itself.
MAIN=main
MAIN_REF=refs/remotes/origin/HEAD
VERBOSE=false
TOOL=integration
BASE_OVERRIDE=''
CACHE_DIR=$ROOT/cache
mkdir -p "$CACHE_DIR"
# shellcheck source=../../../home/common/lib/git-common.sh
. /repo/home/common/lib/git-common.sh

# case <name> <act> <own-commit yes|no>, then the caller dirties the worktree.
open_case() {
  git branch -q "$1" "$base"
  git worktree add -q "$ROOT/wt-$1" "$1"
  cd "$ROOT/wt-$1"
  if [ "$3" = yes ]; then
    printf 'c\n' > c.txt
    git add c.txt
    git commit -qm "C on $1"
  fi
}

close_case() {
  name=$1 act=$2
  if update_needs_stash "$ROOT/wt-$name" "$act"; then said=yes; else said=no; fi
  if [ "$act" = rebase ]; then
    if git rebase main >/dev/null 2>&1; then did=no; else did=yes; fi
    git rebase --abort >/dev/null 2>&1 || :
  else
    if git merge --ff-only main >/dev/null 2>&1; then did=no; else did=yes; fi
  fi
  cd "$ROOT/repo"
  [ "$said" = "$did" ] ||
    fail "$name: predicted a stash was needed=$said, git refused=$did"
  printf '  ok   %-44s predicted %s, git agrees\n' "$name" "$said"
}

open_case rebase-tracked rebase yes
printf 'dirty\n' > u.txt
close_case rebase-tracked rebase

open_case rebase-untracked-stray rebase yes
printf 'stray\n' > stray.txt
close_case rebase-untracked-stray rebase

open_case rebase-untracked-collides rebase yes
printf 'mine\n' > n.txt
close_case rebase-untracked-collides rebase

open_case ff-untracked-stray ff no
printf 'stray\n' > stray.txt
close_case ff-untracked-stray ff

open_case ff-untracked-collides ff no
printf 'mine\n' > n.txt
close_case ff-untracked-collides ff

open_case ff-unrelated-modified ff no
printf 'dirty\n' > u.txt
close_case ff-unrelated-modified ff

open_case ff-incoming-modified ff no
printf 'dirty\n' > a.txt
close_case ff-incoming-modified ff

echo 'PASS stash-is-predicted-the-way-git-decides'
