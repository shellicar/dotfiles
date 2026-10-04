#!/bin/sh
# Runs inside the container, against a repository built here.
#
# The pure suite's listing comes from the fake, which says whatever it was
# written to say. This locks real worktrees and asks the library what blocks
# each one, so what a lock reads as is git's answer, not ours. Nothing is
# removed.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

git worktree add -q --detach "$ROOT/wt-reason" main
git worktree lock --reason 'claude session reason (pid 4242 start 1234567)' "$ROOT/wt-reason"

git worktree add -q --detach "$ROOT/wt-noreason" main
git worktree lock "$ROOT/wt-noreason"

# Quotes and a non-ASCII letter, both of which git C-quotes in the listing.
git worktree add -q --detach "$ROOT/wt-quoted" main
git worktree lock --reason 'has "quotes" and é' "$ROOT/wt-quoted"

# Its directory deleted after locking. git still lists it, still locked, and
# still refuses to remove it, so it has to read as locked.
git worktree add -q --detach "$ROOT/wt-gone" main
git worktree lock --reason 'claude session gone (pid 4343 start 7654321)' "$ROOT/wt-gone"
rm -rf "$ROOT/wt-gone"

git worktree add -q --detach "$ROOT/wt-dirty" main
printf 'not committed\n' > "$ROOT/wt-dirty/dirt.txt"
git worktree lock --reason 'claude session dirty (pid 4444 start 1111111)' "$ROOT/wt-dirty"

echo '--- git worktree list --porcelain ---'
git worktree list --porcelain | sed 's/^/  /'

# shellcheck source=../../../home/common/lib/git-common.sh
. /repo/home/common/lib/git-common.sh

echo '--- outcome ---'
blocks() {
  actual=$(worktree_block_reason "$ROOT/$1")
  [ "$actual" = "$2" ] || fail "$1: expected [$2], got [$actual]"
  printf '  ok   %s: %s\n' "$1" "$actual"
}

blocks wt-reason 'locked: claude session reason (pid 4242 start 1234567)'
blocks wt-noreason 'locked'
blocks wt-quoted 'locked: "has \"quotes\" and \303\251"'
blocks wt-gone 'locked: claude session gone (pid 4343 start 7654321)'
blocks wt-dirty 'worktree has uncommitted changes, locked: claude session dirty (pid 4444 start 1111111)'

echo 'PASS a-lock-is-read-the-way-git-lists-it'
