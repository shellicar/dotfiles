#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a branch cut from main is rebased from where it was cut, not from where a child was"

# feature/base was cut from main and feature/top was cut from base, so every
# commit on base is also on top. That says nothing about base: it was cut from
# main and a rebase onto main is right for it, replaying its own two commits and
# no more.
#
#   main   A - B - C
#   base        \ X1 - X2
#   top                  \ Y1
commit A
commit B A
commit C B
commit X1 B
commit X2 X1
commit Y1 X2

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/feature/base X2
ref_set refs/heads/feature/top Y1

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected="rebase${TAB}B"
actual=$(update_verdict . feature/base)
assert_eq "$actual" "$expected"
