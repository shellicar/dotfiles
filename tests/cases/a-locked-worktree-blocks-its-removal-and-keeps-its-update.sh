#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "git refresh shows a locked worktree's removal as unavailable, and still offers its update"

# git refuses to remove a locked worktree, so offering the removal only sets up
# a failure. It is a [-] row naming the lock. A lock stops nothing else, so the
# trunk is still brought into a locked worktree exactly as into any other.
#
# Run through analyse as well as derive: the lock is found while the facts are
# gathered, and a case that wrote the facts by hand would pass without it.
#
#   main          A - B - C
#   feature/idle      B          (never diverged, worktree /wt/idle, locked)
#   feature/live       \ X1      (its own work, worktree /wt/live, locked)
commit A
commit B A
commit C B
commit X1 B

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/feature/idle B
ref_set refs/heads/feature/live X1

worktree_for refs/heads/main /repo
worktree_for refs/heads/feature/idle /wt/idle
worktree_for refs/heads/feature/live /wt/live
lock_worktree /wt/idle 'claude session feature/idle (pid 4242 start 1234567)'
lock_worktree /wt/live 'claude session feature/live (pid 4343 start 7654321)'

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

NO_FETCH=true
NOW=$(date +%s)

analyse > "$WORK/analyse.out" 2>&1
derive

row() {
  printf '%s' "$ROWS" | awk -F"$TAB" -v op="$1" '$1 == op { print $2 "|" $3 "|" $6; exit }'
}

expected='skip|remove|never diverged from main, locked: claude session feature/idle (pid 4242 start 1234567)'
actual=$(row feature/idleR)
assert_eq "${actual:-<no removal row>}" "$expected"

# The idle branch's update is still offered. Its default follows the removal's,
# which is off for a branch that never diverged, locked or not.
expected='off|ff|1 behind'
actual=$(row feature/idleU)
assert_eq "${actual:-<no update row>}" "$expected"

expected='on|rebase|1 behind'
actual=$(row feature/liveU)
assert_eq "${actual:-<no update row>}" "$expected"
