#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'a pane record with no RS at the end of the input is refused, in a file and in a listing'

# The listing is what tmux prints when its output is cut off part way through
# the last record: the record separator never arrives.
FAKE_SESSIONS="\$0${FUS}work"
tmux_says() {
  case "$*" in
    "-u -L fake list-panes -a -F "*)
      printf '%s\n' "$(snap_record work 0 a lay 0 /a sh '' '' '' '' '' 101)" \
        "work${FUS}0${FUS}a${FUS}lay${FUS}1${FUS}/b${FUS}sh" ;;
    *)
      fake_option "$@" && return 0
      [ $? -eq 2 ] || return 1
      fail "unexpected: tmux $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

dir=$(snapshot_dir fake)
mkdir -p "$dir"

# A file: one whole record, then one whose RS never came. Nothing else to fall
# back to, so there is no snapshot, and the refusal names the file.
printf 'tmux-snapshot 2\nsaved 2026-10-09 12:00\n%s\n%s\n' "$(snap_pane work 0 a 0)" \
  "work${FUS}1${FUS}b${FUS}lay${FUS}0${FUS}/cut" > "$dir/current.snap"
before=$(cksum "$dir/current.snap")
found=$(snapshot_find fake 2>"$WORK/err") && fail "a cut-short file was read: $found"
assert_contains "$(cat "$WORK/err")" "refusing $dir/current.snap: its last pane record does not end with the record separator"
assert_eq "$(cksum "$dir/current.snap")" "$before"

# A listing: the save fails, says why on the server, and writes nothing.
rm "$dir/current.snap"
save_server >/dev/null 2>&1 && fail "a save of a cut-short listing succeeded"
assert_contains "$(fake_option_value @snapshot-error)" 'ended inside a pane record'
[ -e "$dir/current.snap" ] && fail "a snapshot was written from a cut-short listing"
exit 0
