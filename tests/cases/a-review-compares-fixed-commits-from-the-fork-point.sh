#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a review compares fixed commits from the fork point"

# main has moved on since the branch was cut. The link carries the fork point
# and the branch tip as commit ids, so main's later commits cannot appear as the
# branch's own.
commit A
commit B A
commit C A
ref_set refs/heads/main B
ref_set refs/heads/feature/x C

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

main_checkout_root() { printf '/repo'; }
LINK=$WORK/link
opener() { printf '%s' "$2" > "$LINK"; }
REVIEW_OPENER=opener

review_main feature/x main || fail "review_main failed"
assert_eq "$(cat "$LINK")" 'vscode://eamodio.gitlens/link/r/-/compare/A...C?path=/repo'
