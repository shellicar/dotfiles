#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a worktree with uncommitted changes gives a reason not to touch it"

# The pair to standing-in-a-worktree-does-not-protect-it, so removing the one
# guard cannot quietly remove the other.

git_says() {
  case "$*" in
    "-C /some/dirty/worktree status --porcelain") echo " M some-file" ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected='worktree has uncommitted changes'
actual=$(worktree_block_reason /some/dirty/worktree)
assert_eq "$actual" "$expected"
