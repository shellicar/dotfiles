#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a failed rescue leaves an existing rescue branch where it was"

# rescue/<branch> holds commits reachable from nothing else. A later rescue that
# cannot even start must not take the earlier one with it.

ref_set refs/heads/foo commit-on-foo
ref_set refs/heads/rescue/foo the-earlier-rescue

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

run_rescue foo deadbeef 1 '' >"$WORK/out" 2>&1 || :

expected=the-earlier-rescue
actual=$(ref_of refs/heads/rescue/foo || echo '<gone>')
assert_eq "$actual" "$expected"
