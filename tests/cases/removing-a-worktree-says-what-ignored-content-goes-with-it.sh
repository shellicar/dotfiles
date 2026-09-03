#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "removing a worktree says what ignored content goes with it"

# Neither git status --porcelain nor git worktree remove counts ignored files,
# so a worktree whose only extra content is ignored reads as clean and is
# removed with that content inside it. A node_modules is no loss; a .env or a
# built artifact you cannot rebuild is, and this report is the last place that
# can say so before it happens.

git_says() { fail "deriving and printing ask git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# name, worktree, class, ahead, why, behind, block, update action, its detail, ignored
BFACTS="foo${TAB}/wt/foo${TAB}merged${TAB}3${TAB}-${TAB}0${TAB}-${TAB}-${TAB}-${TAB}2 ignored entries: node_modules/, .env$NL"
DFACTS=''

derive
shown=$(say_selected 'Would run')

expected=mentioned
case "$shown" in
  *.env*) actual=mentioned ;;
  *) actual='not mentioned' ;;
esac
assert_eq "$actual" "$expected"
