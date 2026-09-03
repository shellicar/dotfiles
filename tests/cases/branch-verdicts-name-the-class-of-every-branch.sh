#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "branch_verdict names the class of every branch shape"

# This is the function that decides what gets deleted. Every class it can
# return is here, so a change that quietly moves a branch from one class to
# another has to move a line in this file to do it.
#
#   main      A - B - C
#   empty         B          (sitting on main's history, nothing of its own)
#   unmerged        \ U1     (own work, not in main)
#   merged      squashed into C, tip still its own commits
commit A
commit B A
commit C B
commit U1 B

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/empty B
ref_set refs/heads/unmerged U1

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

MAIN_IDX=$WORK/idx
: > "$MAIN_IDX"
WT_MAP=''

# Computed before the read: a here-doc is expanded as part of setting up the
# command it feeds, so the substitution would run with IFS already set to tab.
class_of() {
  v=$(branch_verdict "$1")
  IFS="$TAB" read -r class _ _ _ _ <<EOF
$v
EOF
  printf '%s' "$class"
}

expected="empty=empty unmerged=unmerged"
actual="empty=$(class_of empty) unmerged=$(class_of unmerged)"
assert_eq "$actual" "$expected"
