#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a rescue replays the branch, not a tag that shares its name"

# git resolves a short name by searching, and reaches refs/tags before
# refs/heads. A rescue that hands git the short name replays the tag and then
# deletes the branch, so what it preserved is not what it destroyed.

ref_set refs/tags/foo commit-on-the-tag
ref_set refs/heads/foo commit-on-the-branch

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

run_rescue foo deadbeef 1 '' >"$WORK/out" 2>&1 || :

expected="replayed-onto-refs/remotes/origin/HEAD-from-commit-on-the-branch"
actual=$(ref_of refs/heads/rescue/foo || echo '<no such branch>')
assert_eq "$actual" "$expected"
