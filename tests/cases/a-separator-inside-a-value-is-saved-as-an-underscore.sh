#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'a US or RS inside a cwd or @status is saved as _, and the snapshot keeps exactly its panes'

# Two panes. The first has US and RS, two of each, in its cwd and in @status,
# with a newline as well; the second is plain. tmux renders the listing from
# the format the library asks for, as it would.
FAKE_SESSIONS="\$0${FUS}work"
STATUS="a${FRS}b${FUS}c${FRS}d${FUS}e${NL}f"
CWD="/w/x${FUS}y${FRS}z"
tmux_says() {
  case "$*" in
    "-u -L fake list-panes -a -F "*)
      fmt=$7
      fake_render "$fmt" session_name work window_index 0 window_name code window_layout lay \
        pane_index 0 pane_current_path "$CWD" pane_current_command sh \
        @title '' @colour '' @state '' @role '' @status "$STATUS" pane_pid 101
      fake_render "$fmt" session_name work window_index 0 window_name code window_layout lay \
        pane_index 1 pane_current_path /w pane_current_command sh \
        @title '' @colour '' @state '' @role '' @status '' pane_pid 102 ;;
    *)
      fake_option "$@" && return 0
      [ $? -eq 2 ] || return 1
      fail "unexpected: tmux $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

PROC_ROOT=$WORK/proc
mkdir -p "$PROC_ROOT/self"
: > "$PROC_ROOT/self/stat"
fake_option "-u" "-L" fake set-option -s @snapshot-error 'an earlier failure'

save_server >/dev/null 2>&1 || fail "the save failed"
fake_option_is_set @snapshot-error && fail "the save left @snapshot-error set"

file=$(snapshot_dir fake)/current.snap
snapshot_accepts "$file" || fail "the file it wrote was refused"
assert_eq "$(sed 1,2d "$file")" \
  "$(snap_record work 0 code lay 0 "/w/x_y_z" sh '' '' '' '' '' "a_b_c_d_e${NL}f")
$(snap_record work 0 code lay 1 /w sh '' '' '' '' '' '')"

panes=$(snapshot_panes "$file")
assert_eq "$(count_records "$panes")" 2
parse_pane "${panes%%"$RS"*}" || fail "the first record did not parse"
assert_eq "$P_PATH" '/w/x_y_z'
assert_eq "$P_STATUS" "a_b_c_d_e${NL}f"
