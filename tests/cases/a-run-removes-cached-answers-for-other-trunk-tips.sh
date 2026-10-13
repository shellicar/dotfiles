#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a run removes the cached merge answers for every trunk tip but the current one"

# The answers are keyed by the trunk's tip, so once it moves they are never read
# again. resolve_main, which every command goes through, removes them. The
# answers for the current tip stay, and so does everything else in the cache.
#
#   main   A - B      the trunk was at A, and is now at B
commit A
commit B A
ref_set refs/heads/main B
ref_set refs/remotes/origin/main B

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

mkdir -p "$CACHE_DIR/in-main/A" "$CACHE_DIR/in-main/B"
echo yes > "$CACHE_DIR/in-main/A/X1"
echo no > "$CACHE_DIR/in-main/B/X2"
# The flat layout an earlier version of this wrote: one file per tip and commit.
echo yes > "$CACHE_DIR/in-main/A-X1"
echo kept > "$CACHE_DIR/remove-output"

BASE_OVERRIDE=main
resolve_main

[ -e "$CACHE_DIR/in-main/A" ] && fail "the old tip's answers survived"
[ -e "$CACHE_DIR/in-main/A-X1" ] && fail "the old flat entry survived"
[ -f "$CACHE_DIR/in-main/B/X2" ] || fail "the current tip's answers were removed"
[ -f "$CACHE_DIR/remove-output" ] || fail "something outside in-main was removed"
:
