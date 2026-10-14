#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "branches cut from commits that later landed are rebased from the landed commit"

# Several branches were cut from a local main holding commits nobody had
# pushed. Those commits then reached origin as squash merges under other
# commits, so every branch still holds them and none of them is in main's
# history. Their work is in main, so another branch holding them is no reason
# to refuse, and the rebase starts above them rather than replaying them.
#
#   main     A - S                  S is the squash of L1 and L2
#   (old)     \ L1 - L2             L2's work is in main; L1 tested alone is not
#   p                  \ P1         worktree /wt/p
#   q                  \ Q1 - Q2    worktree /wt/q
#   r                  \ R1         published
commit A
commit S A
commit L1 A
commit L2 L1
commit P1 L2
commit Q1 L2
commit Q2 Q1
commit R1 L2
lands L2

ref_set refs/heads/main S
ref_set refs/remotes/origin/HEAD S
ref_set refs/heads/p P1
ref_set refs/heads/q Q2
ref_set refs/heads/r R1
ref_set refs/remotes/origin/r R1
worktree_for refs/heads/main /repo
worktree_for refs/heads/p /wt/p
worktree_for refs/heads/q /wt/q

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

WALK_DEPTH=50

assert_eq "$(update_verdict /wt/p p)" "rebase${TAB}L2"
assert_eq "$(update_verdict /wt/q q)" "rebase${TAB}L2"
assert_eq "$(update_verdict . r)" "rebase${TAB}L2"
# What the rebase replays: the branch's own commits, not L1 and L2.
assert_eq "$(rebase_count L2 q)" 2
