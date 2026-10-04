#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a worktree that is dirty and locked names both reasons, the changes then the lock"

# Either one blocks the removal. Naming only the first leaves the other to be
# found when the first is dealt with, so both are on the row.

git_says() {
  case "$*" in
    "-C /wt/both status --porcelain") echo " M some-file" ;;
    "worktree list --porcelain")
      printf 'worktree /wt/both\nHEAD some-tip\nbranch refs/heads/feature/both\nlocked claude session feature/both (pid 4242 start 1234567)\n\n' ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected='worktree has uncommitted changes, locked: claude session feature/both (pid 4242 start 1234567)'
actual=$(worktree_block_reason /wt/both)
assert_eq "$actual" "$expected"
