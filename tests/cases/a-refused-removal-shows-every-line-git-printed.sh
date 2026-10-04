#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a refused removal shows every line git printed, each under the skipped line"

# git's refusal of a locked worktree is two lines: the reason, then how to get
# past it. Cutting to the first would drop the second.

git_says() { fail "printing what git said asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

printf '%s\n%s\n' \
  'fatal: cannot remove a locked working tree, lock reason: claude session x (pid 4242 start 1234567)' \
  "use 'remove -f -f' to override or unlock first" > "$CACHE_DIR/remove-output"

expected="     ↳ fatal: cannot remove a locked working tree, lock reason: claude session x (pid 4242 start 1234567)
     ↳ use 'remove -f -f' to override or unlock first"
actual=$(say_removal_output)
assert_eq "$actual" "$expected"
