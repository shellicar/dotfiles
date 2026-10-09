#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'a save moves current.snap to previous.snap, writes the new one, and never touches the JSON files'

FAKE_SESSIONS="\$0$FUS
\$1${FUS}a:b"
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

dir=$(snapshot_dir fake)
mkdir -p "$dir"
printf '{"old":1}\n' > "$dir/current.json"
printf '{"old":0}\n' > "$dir/previous.json"
printf '{"half' > "$dir/.writing.42.json"
json_before=$(cksum "$dir/current.json" "$dir/previous.json" "$dir/.writing.42.json")

FAKE_PANES="\$1${FUS}2${FUS}two${FUS}lay${FUS}0${FUS}/b${FUS}sh${FUS}102
\$0${FUS}0${FUS}one${FUS}lay${FUS}0${FUS}/a${FUS}sh${FUS}101"
out=$(save_server 2>/dev/null) || fail "first save failed"
first=$(cat "$dir/current.snap")

# The summary names the "" session so it can be seen.
assert_contains "$out" "\"\"${NL}  0  one  (1 pane)"

# The save time once, on its own line; then the panes sorted, the "" session
# first, every field where it belongs, the empty @ fields at the end included.
case $(sed -n 2p "$dir/current.snap") in
  'saved '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' '[0-9][0-9]:[0-9][0-9]) ;;
  *) fail "the second line is not the save time: $(sed -n 2p "$dir/current.snap")" ;;
esac
assert_eq "$(sed 1,2d "$dir/current.snap")" \
  "$(snap_line '' 0 one lay 0 /a sh '' '' '' '' '' '')
$(snap_line a:b 2 two lay 0 /b sh '' '' '' '' '' '')"

FAKE_PANES="$FAKE_PANES
\$0${FUS}0${FUS}one${FUS}lay${FUS}1${FUS}/c${FUS}sh${FUS}103"
save_server >/dev/null 2>&1 || fail "second save failed"
assert_eq "$(cat "$dir/previous.snap")" "$first"
assert_eq "$(sed 1,2d "$dir/current.snap" | wc -l | tr -d ' ')" 3

assert_eq "$(cksum "$dir/current.json" "$dir/previous.json" "$dir/.writing.42.json")" "$json_before"
files=''
for f in "$dir"/* "$dir"/.[!.]*; do [ -e "$f" ] && files="$files${f##*/} "; done
assert_eq "$files" 'current.json current.snap previous.json previous.snap .writing.42.json '
