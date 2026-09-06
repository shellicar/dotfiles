#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a trunk ahead of its remote is reported, and says whether a branch holds the work"

# The accidental commit to main. Every other verdict is measured against the
# remote trunk and stays correct, so nothing else notices, and you are left with
# a decision only you can make: push those commits, or move them off.
#
#   origin/main   A - B
#   main                \ C        (not pushed)
#   feature/x                \ X1
commit A
commit B A
commit C B
commit X1 C

ref_set refs/remotes/origin/main B
ref_set refs/remotes/origin/HEAD B
ref_set refs/heads/main C

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

alone=$(local_trunk_ahead)

ref_set refs/heads/feature/x X1
held=$(local_trunk_ahead)

expected="alone=[main is 1 ahead of its remote, on no other branch] held=[main is 1 ahead of its remote, and feature/x is built on those commits]"
actual="alone=[$alone] held=[$held]"
assert_eq "$actual" "$expected"
