#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "git cleanup reports a locked worktree as blocked, names the lock, and plans nothing for it"

#   main          A - B
#   feature/done  A          (in main, worktree /wt/done, locked)
commit A
commit B A
ref_set refs/heads/main B
ref_set refs/remotes/origin/HEAD B
ref_set refs/heads/feature/done A
worktree_for refs/heads/feature/done /wt/done
lock_worktree /wt/done 'claude session feature/done (pid 4242 start 1234567)'

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-cleanup
. "$REPO/home/common/bin/git-cleanup"

APPLY=true
MERGED_COUNT=0
out=$(do_delete feature/done /wt/done '' merged '[0 ahead, 5 days ago]' true --apply MERGED_COUNT; printf 'plan=[%s]' "$PLAN")

assert_contains "$out" 'locked: claude session feature/done (pid 4242 start 1234567), blocked'
assert_contains "$out" 'plan=[]'
