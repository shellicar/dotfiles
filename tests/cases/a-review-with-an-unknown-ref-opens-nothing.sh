#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a review with an unknown ref opens nothing"

# A mistyped name has to stop git review before VS Code opens, or it shows up
# as an empty comparison there instead of an error here.
commit A
ref_set refs/heads/main A
ref_set refs/heads/feature/x A

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

OPENED=$WORK/opened
opener() { : > "$OPENED"; }
REVIEW_OPENER=opener

for args in "feature/typo main" "feature/x mian"; do
  # shellcheck disable=SC2086 # two refs, split on purpose
  if (review_main $args) 2>/dev/null; then
    fail "review_main $args succeeded"
  fi
  [ ! -e "$OPENED" ] || fail "review_main $args opened VS Code"
done
