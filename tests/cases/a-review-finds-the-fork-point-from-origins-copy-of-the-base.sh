#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a review finds the fork point from origin's copy of the base"

# The local main is behind: the branch was cut from origin/main at B, and the
# local main is still at A. A fork point from the local main would be A and
# list B as the branch's own.
commit A
commit B A
commit C B
ref_set refs/heads/main A
ref_set refs/remotes/origin/main B
ref_set refs/heads/feature/x C

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

review_folder() { printf '/repo'; }
LINK=$WORK/link
opener() { printf '%s' "$2" > "$LINK"; }
REVIEW_OPENER=opener

review_main feature/x main || fail "review_main failed"
assert_eq "$(cat "$LINK")" 'vscode://eamodio.gitlens/link/r/-/compare/B...feature/x?path=/repo'
