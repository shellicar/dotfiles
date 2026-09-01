#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "--old evaluates a branch the distance and age cap would skip"

# The cap exists because the content walk gets both expensive and unreliable
# once main has moved a long way. --old says look anyway, so a branch that is
# both far behind and long untouched has to stop being capped.

NOW=1000000000
MAX_DISTANCE=100
MAX_AGE_DAYS=30

git_says() {
  case "$*" in
    # Far past the distance cap.
    "rev-list --count refs/remotes/origin/HEAD ^refs/heads/ancient") echo 500 ;;
    # And last touched a year before now.
    "log -1 --format=%ct refs/heads/ancient") echo 968464000 ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

EVALUATE_OLD=true
branch_beyond_cap refs/heads/ancient && actual=capped || actual=evaluated

expected=evaluated
assert_eq "$actual" "$expected"
