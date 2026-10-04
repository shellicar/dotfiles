#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a review takes a base that is only on origin"

# The local main has been deleted, which is common; origin/main is the only
# copy, and the caller names it. The link starts from where the branch left it.
commit A
commit B A
ref_set refs/remotes/origin/main A
ref_set refs/heads/feature/x B

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

review_folder() { printf '/repo'; }
LINK=$WORK/link
opener() { printf '%s' "$2" > "$LINK"; }
REVIEW_OPENER=opener

review_main feature/x origin/main || fail "review_main refused origin/main"
assert_eq "$(cat "$LINK")" 'vscode://eamodio.gitlens/link/r/-/compare/A...feature/x?path=/repo'
