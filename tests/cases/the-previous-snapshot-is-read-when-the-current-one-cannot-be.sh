#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'current.snap is read first, previous.snap when current is missing or refused, the JSON files never'

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

dir=$(snapshot_dir fake)
mkdir -p "$dir"

# Only the old JSON: no snapshot.
printf '{"panes":[]}\n' > "$dir/current.json"
printf '{"panes":[]}\n' > "$dir/previous.json"
snapshot_find fake >/dev/null 2>&1 && fail "the JSON files counted as a snapshot"

# Only previous.snap.
snap_file "$dir/previous.snap" "$(snap_pane old 0 a 0)"
assert_eq "$(snapshot_find fake)" "$dir/previous.snap"

# Both: current wins.
snap_file "$dir/current.snap" "$(snap_pane new 0 a 0)"
assert_eq "$(snapshot_find fake)" "$dir/current.snap"

# current refused: previous, and the refusal is said.
printf 'garbage\n' > "$dir/current.snap"
found=$(snapshot_find fake 2>"$WORK/err")
assert_eq "$found" "$dir/previous.snap"
assert_contains "$(cat "$WORK/err")" "refusing $dir/current.snap"
