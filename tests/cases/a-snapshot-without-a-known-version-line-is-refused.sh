#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'a file with no version line, or one this does not know, is refused by name'

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

dir=$(snapshot_dir fake)
mkdir -p "$dir"

# A pane line where the version line should be: nothing in it is read.
snap_pane work 0 code 0 > "$dir/current.snap"
msg=$(snapshot_accepts "$dir/current.snap" 2>&1) && fail "a file with no version line was accepted"
assert_contains "$msg" "refusing $dir/current.snap: no version line"
assert_contains "$msg" "work"

printf 'tmux-snapshot 3\n%s\n' "$(snap_pane work 0 code 0)" > "$dir/current.snap"
msg=$(snapshot_accepts "$dir/current.snap" 2>&1) && fail "an unknown version was accepted"
assert_contains "$msg" "refusing $dir/current.snap: its version line is 'tmux-snapshot 3'"

: > "$dir/current.snap"
msg=$(snapshot_accepts "$dir/current.snap" 2>&1) && fail "an empty file was accepted"
assert_contains "$msg" "refusing $dir/current.snap: no version line"

# Neither file is readable, so there is no snapshot, and neither is changed.
cp "$dir/current.snap" "$dir/previous.snap"
printf 'tmux-snapshot 3\n' > "$dir/current.snap"
before=$(cksum "$dir/current.snap" "$dir/previous.snap")
found=$(snapshot_find fake 2>/dev/null) && fail "found a snapshot in refused files: $found"
assert_eq "$(cksum "$dir/current.snap" "$dir/previous.snap")" "$before"
