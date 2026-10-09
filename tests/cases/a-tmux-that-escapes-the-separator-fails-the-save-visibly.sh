#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'a tmux that prints the field separator escaped fails the save, marks it, and writes nothing'

FAKE_TMUX_35=1
FAKE_SESSIONS="\$0${FUS}work"
FAKE_PANES="\$0${FUS}0${FUS}code${FUS}lay${FUS}0${FUS}/w${FUS}sh${FUS}101
\$0${FUS}0${FUS}code${FUS}lay${FUS}1${FUS}/w${FUS}sh${FUS}102"
tmux_says() {
  [ "$*" = -V ] && { echo 'tmux 3.5a'; return 0; }
  fake_listing "$@" && return 0
  [ $? -eq 2 ] || return 1
  fake_option "$@" && return 0
  [ $? -eq 2 ] || return 1
  fail "unexpected: tmux $*"
}

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

save_server >/dev/null 2>&1 && fail "a save of unreadable rows succeeded"
assert_contains "$(fake_option_value @snapshot-error)" 'tmux 3.5a'
[ -e "$(snapshot_dir fake)" ] && fail "a snapshot directory was written"

# Restore stops before planning on rows it cannot read.
dir=$(snapshot_dir fake)
mkdir -p "$dir"
printf 'tmux-snapshot 2\n%s\n' "$(snap_pane work 0 code 0)" > "$dir/current.snap"
err=$( (cmd_restore) 2>&1) && fail "a restore planned against unreadable rows"
assert_contains "$err" 'not supported'
