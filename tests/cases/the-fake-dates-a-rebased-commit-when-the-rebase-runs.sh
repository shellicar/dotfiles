#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "the fake dates a commit its rebase makes at the time the rebase runs"

# A rebase writes new commits, and git dates each one when it is written, not
# with the date of the commit it replays.
#
#   main      A - M
#   feature    \ F
NOW=1000000000
commit A
commit M A
commit F A
ref_set refs/heads/main M
ref_set refs/heads/feature F

git switch -q -c rebased refs/heads/feature
NOW=1000086400
git rebase -q --onto main A

actual=$(git rev-list --no-commit-header -1 --format=%ct refs/heads/rebased)
expected=1000086400
assert_eq "$actual" "$expected"
