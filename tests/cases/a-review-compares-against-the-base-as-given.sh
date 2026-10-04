#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a review compares against the base as given"

# origin/main exists and is ahead of the local main. The base is the caller's
# choice: given main, the link starts from where the branch left main (A), not
# where it left origin's copy (B).
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
assert_eq "$(cat "$LINK")" 'vscode://eamodio.gitlens/link/r/-/compare/A...feature/x?path=/repo'
