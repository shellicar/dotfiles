#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a tangle is reported without claiming which branch came first"

# upper was cut from lower's FIRST commit, so upper does not contain lower's
# tip and each branch's fork point sits on the other. Both are told they are
# tangled with the other, and only one of those could be a cut-from. Saying
# which would be a coin flip, and following it would rebase onto the wrong
# branch, so neither line claims a direction.
#
#   main   A - B - C
#   lower        \ L1 - L2
#   upper             \ P1        (cut from L1, not from L2)
commit A
commit B A
commit C B
commit L1 B
commit L2 L1
commit P1 L1

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/lower L2
ref_set refs/heads/upper P1

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected="lower=[none${TAB}shares history with upper past main] upper=[none${TAB}shares history with lower past main]"
actual="lower=[$(update_verdict . lower)] upper=[$(update_verdict . upper)]"
assert_eq "$actual" "$expected"
