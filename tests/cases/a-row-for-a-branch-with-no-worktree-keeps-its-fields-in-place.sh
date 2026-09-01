#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a row for a branch with no worktree keeps its fields in place"

# Tab is IFS whitespace, so a run of tabs is one delimiter and an empty field
# vanishes, shifting every field after it. The worktree field is empty for every
# branch that has none, and the reason column then lands in it: the plan tries
# to remove a worktree called "remote gone", and a rescue reads an empty count
# and replays nothing before deleting the branch.

git_says() { fail "no git call belongs in building or reading a row: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

ROWS=''
emit fooR on remove 'remove foo' '' 'remote gone'

IFS="$TAB" read -r op state kind action target why <<EOF
$ROWS
EOF

expected='remote gone'
actual=$why
assert_eq "$actual" "$expected"
