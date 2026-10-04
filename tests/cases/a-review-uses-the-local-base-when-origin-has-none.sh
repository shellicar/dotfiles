#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a review uses the local base when origin has none"

# No remote copy of the base: no remote at all, or a base never pushed. The
# local branch is the only copy, so the link names it as given.
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
assert_eq "$(cat "$LINK")" 'vscode://eamodio.gitlens/link/r/-/compare/main...feature/x?path=/repo'
