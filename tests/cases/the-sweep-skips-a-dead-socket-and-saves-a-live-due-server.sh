#!/bin/sh
# The sweep's live behaviour, tmux faked: a dead socket (display-message fails)
# is skipped with no save, and a live server past the gates is saved through the
# real loop and watchdog, which then records @snapshot-last-save and throttles
# the next tick.
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'the sweep skips a dead socket and saves a live due server'

tmux_says() {
  fake_listing "$@" && return 0
  [ $? -eq 2 ] || return 1
  fake_display "$@" && return 0
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
dir=$(snapshot_dir fake)

# A dead socket: no sessions, so the read fails and the server is skipped.
FAKE_SESSIONS=''
sweep_server fake 2000000000 300 30 || fail "the dead-socket skip returned non-zero"
[ -f "$dir/current.snap" ] && fail "a dead socket was saved"
fake_option_is_set @snapshot-last-save && fail "a dead socket recorded a last save"

# A live, non-trivial server, up long before the interval and never saved, swept
# through the real loop (server_labels names it). It is due, so it saves.
server_labels() { printf '%s\n' fake; }
FAKE_SESSIONS="\$0${FUS}work"
FAKE_PANES="\$0${FUS}0${FUS}code${FUS}lay${FUS}0${FUS}/w${FUS}sh${FUS}101
\$0${FUS}0${FUS}code${FUS}lay${FUS}1${FUS}/w${FUS}sh${FUS}102"
FAKE_START_TIME=1000000000

tmux_snapshot_sweep 300 30 10
[ -f "$dir/current.snap" ] || fail "a live due server was not saved"
fake_option_is_set @snapshot-last-save || fail "the save did not record @snapshot-last-save"
case $(fake_option_value @snapshot-last-save) in '' | *[!0-9]*) fail "last save is not an epoch" ;; esac
last=$(fake_option_value @snapshot-last-save)

# An immediate second sweep: the save it just recorded is far newer than the
# throttle allows, so nothing is saved again.
tmux_snapshot_sweep 300 30 10
assert_eq "$(fake_option_value @snapshot-last-save)" "$last"
