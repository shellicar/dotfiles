#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "the fake fails rev-list --count <a> ^<b> when either side names nothing"

# git answers "fatal: bad revision" with 128 for either side. Answering a count
# instead would let a typo in the code under test pass as a distance.
#
#   main   A - M
commit A
commit M A
ref_set refs/heads/main M

git rev-list --count main ^nosuch >/dev/null 2>&1
excluded=$?
git rev-list --count nosuch ^main >/dev/null 2>&1
included=$?

expected="excluded=128 included=128"
actual="excluded=$excluded included=$included"
assert_eq "$actual" "$expected"
