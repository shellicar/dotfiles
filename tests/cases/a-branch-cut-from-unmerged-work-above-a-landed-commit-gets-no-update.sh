#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a branch cut from another branch's unmerged work is still refused, landed commits or not"

# Commits under a landed commit count as in main, and nothing more does.
# feature/a has work of its own above the landed commit, checked out in a
# worktree, and feature/b was cut from it. Rebasing b would replay a's commit
# under a new id and publish it as b's, so b is refused, exactly as it would be
# with no landed commit at all. a itself is rebased from the landed commit.
#
#   main        A - S                S is the squash of L1
#   (old)        \ L1                L1's work is in main
#   feature/a          \ X1          worktree /wt/a
#   feature/b                \ Y1    worktree /wt/b
commit A
commit S A
commit L1 A
commit X1 L1
commit Y1 X1
lands L1

ref_set refs/heads/main S
ref_set refs/remotes/origin/HEAD S
ref_set refs/heads/feature/a X1
ref_set refs/heads/feature/b Y1
worktree_for refs/heads/main /repo
worktree_for refs/heads/feature/a /wt/a
worktree_for refs/heads/feature/b /wt/b

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

WALK_DEPTH=50

assert_eq "$(update_verdict /wt/b feature/b)" "none${TAB}shares history with feature/a past main"
assert_eq "$(update_verdict /wt/a feature/a)" "rebase${TAB}L1"
