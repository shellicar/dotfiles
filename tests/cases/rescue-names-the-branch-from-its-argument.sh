#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "the rescued commits land on a branch named after the branch rescued"

# `local a=$1 b="x/$a"` evaluates every assignment before any takes effect, so
# the second reads the caller's `a` rather than the argument. The rescue branch
# was then named after whatever the caller called its loop variable.

branch=SOMETHING_ELSE
ref_set refs/heads/foo commit-on-foo

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

run_rescue foo deadbeef 1 '' >"$WORK/out" 2>&1 || :

expected="replayed-onto-refs/remotes/origin/HEAD-from-commit-on-foo"
actual=$(ref_of refs/heads/rescue/foo || echo '<no such branch>')
assert_eq "$actual" "$expected"
