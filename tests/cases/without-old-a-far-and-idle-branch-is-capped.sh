#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "without --old a branch both far behind and long idle is capped"

# The pair to old-evaluates-a-branch-the-cap-would-skip. Distance and age both
# have to hold: a recent branch on a busy repo is far back but still worth
# comparing, and an old branch on a quiet repo is only a few commits to check.

NOW=1000000000
MAX_DISTANCE=100
MAX_AGE_DAYS=30

git_says() {
  case "$*" in
    "rev-list --count refs/remotes/origin/HEAD ^refs/heads/ancient") echo 500 ;;
    "log -1 --format=%ct refs/heads/ancient") echo 968464000 ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

branch_beyond_cap refs/heads/ancient && actual=capped || actual=evaluated

expected=capped
assert_eq "$actual" "$expected"
