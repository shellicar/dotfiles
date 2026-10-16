#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a merged branch that was never pushed reads merged, tracks no remote branch"

# A branch with no upstream has no remote that could be gone or still there, so
# neither of the other two messages applies.
#
#   main   A - B - C
#   topic        \ T1    content landed in main as C
commit A
commit B A
commit C B
commit T1 B
lands T1

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/topic T1

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

# No upstream configured: the fake's default git_config_says answers nothing.

v=$(branch_verdict topic)
IFS="$TAB" read -r class n _ gone _ <<EOF
$v
EOF
branch_reason topic "$class" "$n" "$gone"

assert_eq "$class $REASON" "merged merged, tracks no remote branch"
