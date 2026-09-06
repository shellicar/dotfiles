#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a trunk level with its remote says nothing"

# The pair to a-trunk-ahead-of-its-remote-is-reported. A warning that fires on
# the ordinary case is one you learn to read past.
commit A
commit B A

ref_set refs/remotes/origin/main B
ref_set refs/remotes/origin/HEAD B
ref_set refs/heads/main B

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected=''
actual=$(local_trunk_ahead)
assert_eq "$actual" "$expected"
