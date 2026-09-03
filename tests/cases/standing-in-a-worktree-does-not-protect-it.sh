#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a clean worktree is removable whether or not you are standing in it"

# Decided behaviour, pinned so it cannot drift back: git will remove the
# worktree you are in, and the only casualty is a shell whose directory has
# gone. Uncommitted work is the one thing that blocks.

git_says() {
  case "$*" in
    "-C /some/clean/worktree status --porcelain") : ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected=''
actual=$(worktree_block_reason /some/clean/worktree)
assert_eq "$actual" "$expected"
