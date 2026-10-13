#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a branch that shares no history with main is never merge-tested, and says so"

# git merge-tree refuses to merge unrelated histories, and a git failure there
# stops the command. So a branch with no merge base, a pages branch for
# instance, has to be answered before merge-tree is asked: it has no landed
# commit, and its update says it shares no history with main.
#
#   main    A - B
#   pages   P1 - P2        a separate root, checked out in a worktree
commit A
commit B A
commit P1
commit P2 P1

ref_set refs/heads/main B
ref_set refs/remotes/origin/HEAD B
ref_set refs/heads/pages P2
worktree_for refs/heads/main /repo
worktree_for refs/heads/pages /wt/pages

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

WALK_DEPTH=50

assert_eq "$(landed_commit refs/heads/pages)" none
assert_eq "$(update_verdict /wt/pages pages)" "none${TAB}shares no history with main"
grep -q '^merge-tree' "$GIT_LOG" && fail "merge-tree was asked about a branch with no history in common with main"
:
