#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "naming a branch exempts it from the distance and age cap"

# The cap is there to keep a whole-repository run quick by skipping branches
# unlikely to resolve. Asking about one branch says the same thing --old says:
# look properly, the cost is one branch.

NOW=1000000000
MAX_DISTANCE=100
MAX_AGE_DAYS=30

git_says() { fail "a named branch should be exempt before any git call: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

ONLY_BRANCHES='ancient'
branch_beyond_cap refs/heads/ancient && actual=capped || actual=evaluated

expected=evaluated
assert_eq "$actual" "$expected"
