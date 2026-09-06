#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a branch on the trunk's unpushed commits is told that, not that it shares history with the trunk"

# The trunk counts as live because it is always checked out, so the general
# wording came out as "shares history with main past main", which says nothing
# and points nowhere. Naming the state is the whole fix: the reader decides
# whether to push those commits or move them off, and the two are opposites.
#
#   origin/main   A - B
#   main                \ C        (not pushed)
#   feature/x                \ X1
commit A
commit B A
commit C B
commit X1 C

ref_set refs/remotes/origin/main B
ref_set refs/remotes/origin/HEAD B
ref_set refs/heads/main C
ref_set refs/heads/feature/x X1

# Deliberately no worktree for main. The trunk is protected because it is the
# trunk, not because someone is standing on it: with a single worktree you are
# usually standing on the branch, which is exactly when this has to hold.

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected="none${TAB}on unpushed commits of local main"
actual=$(update_verdict . feature/x)
assert_eq "$actual" "$expected"
