#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'a failed save sets @snapshot-error on its server, a successful one unsets it, a skipped one leaves it'

FAKE_SESSIONS="\$0${FUS}work"
FAKE_PANES="\$0${FUS}0${FUS}code${FUS}lay${FUS}0${FUS}/w${FUS}sh${FUS}101
\$0${FUS}0${FUS}code${FUS}lay${FUS}1${FUS}/w${FUS}sh${FUS}102"
tmux_says() {
  fake_listing "$@" && return 0
  [ $? -eq 2 ] || return 1
  fake_option "$@" && return 0
  [ $? -eq 2 ] || return 1
  fail "unexpected: tmux $*"
}

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

PROC_ROOT=$WORK/proc
mkdir -p "$PROC_ROOT/self"
: > "$PROC_ROOT/self/stat"

# A file where the label's directory should be: the save cannot write.
dir=$(snapshot_dir fake)
mkdir -p "${dir%/*}"
: > "$dir"
save_server >/dev/null 2>&1 && fail "a save that could not write succeeded"
fake_option_is_set @snapshot-error || fail "the failed save did not set @snapshot-error"
assert_contains "$(fake_option_value @snapshot-error)" "cannot create $dir"

# One pane is skipped, not failed: the mark stays.
saved_panes=$FAKE_PANES
FAKE_PANES=$(printf '%s\n' "$saved_panes" | sed -n 1p)
save_server >/dev/null 2>&1 || fail "a skipped save failed"
fake_option_is_set @snapshot-error || fail "a skipped save cleared @snapshot-error"

# The directory can be written again: the save succeeds and the mark goes.
FAKE_PANES=$saved_panes
rm "$dir"
save_server >/dev/null 2>&1 || fail "the save failed"
fake_option_is_set @snapshot-error && fail "a successful save left @snapshot-error set"
[ -f "$dir/current.snap" ] || fail "no snapshot written"
