#!/bin/sh
# Runs inside the container, against a repository built here.
#
# When git refuses a removal, the line saying it was skipped is followed by
# what git said, so the reason is on screen rather than thrown away. The plan
# would block each of these, so the plan is written here by hand and handed to
# run_plan: this is about carrying a removal out when git refuses it.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

# held: its worktree is locked, so git refuses to remove it.
branch held
commit H1 held.txt
git switch -q main
worktree_for held
git worktree lock --reason 'claude session held (pid 4242 start 1234567)' "$ROOT/wt-held"

# busy: checked out in a worktree, so git refuses to delete the branch.
branch busy
commit B1 busy.txt
git switch -q main
worktree_for busy

# parked: a worktree with no branch, locked.
git worktree add -q --detach "$ROOT/wt-parked" main
git worktree lock --reason 'claude session parked (pid 4343 start 7654321)' "$ROOT/wt-parked"

# shellcheck source=../../../home/common/lib/git-common.sh
. /repo/home/common/lib/git-common.sh
TAB=$(printf '\t')
CACHE_DIR="$(git rev-parse --git-dir)/cleanup-cache"
mkdir -p "$CACHE_DIR"
REMOVED_COUNT=0
RESCUED_COUNT=0
PLAN=''
plan_add delete held - - "$ROOT/wt-held"
plan_add delete busy - - -
plan_add detached wt-parked - - "$ROOT/wt-parked"

echo '--- run_plan ---'
# The library is written for set -u alone, and the refusals are the point.
set +e
out=$(run_plan 2>&1)
set -e
printf '%s\n' "$out" | sed 's/^/  /'

echo '--- outcome ---'
# Each skipped line, then the line under it, which has to be git's own words:
# the lock reason, or the worktree holding the branch, is something only git
# could have put there.
under() {
  printf '%s\n' "$out" | awk -v s="$1" 'found { print; exit } index($0, s) { found = 1 }'
}

line=$(under 'held: worktree remove failed, skipped')
case "$line" in
  '     ↳ '*'claude session held (pid 4242 start 1234567)'*) printf '  ok   held shows the lock reason\n' ;;
  *) fail "under held's skipped line: [$line]" ;;
esac

line=$(under 'busy: branch delete failed, skipped')
case "$line" in
  '     ↳ '*"$ROOT/wt-busy"*) printf '  ok   busy shows the worktree holding it\n' ;;
  *) fail "under busy's skipped line: [$line]" ;;
esac

line=$(under 'wt-parked: worktree remove failed, skipped')
case "$line" in
  '     ↳ '*'claude session parked (pid 4343 start 7654321)'*) printf '  ok   wt-parked shows the lock reason\n' ;;
  *) fail "under wt-parked's skipped line: [$line]" ;;
esac

exists refs/heads/held
exists refs/heads/busy
[ -d "$ROOT/wt-held" ] || fail "wt-held was removed"
[ -d "$ROOT/wt-parked" ] || fail "wt-parked was removed"

echo 'PASS a-refused-removal-shows-what-git-said'
