#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a review compares from the fork point"

# main has moved on since the branch was cut. The base side of the link is the
# fork point as a commit id, so main's later commits cannot appear as the
# branch's own. The branch side is its name.
commit A
commit B A
commit C A
ref_set refs/heads/main B
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
