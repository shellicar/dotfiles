#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'without /proc, one ps table is read and each command is kept whole'

# This is the reader a Mac uses. The table is what `ps -ww -axo
# pid=,ppid=,command=` prints: right-aligned pids, then the command with its
# own spaces. Whether a Mac's ps prints exactly this is not tested here.
guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

PS_CALLS=$WORK/ps-calls
ps() {
  echo x >> "$PS_CALLS"
  [ "$*" = '-ww -axo pid=,ppid=,command=' ] || fail "unexpected: ps $*"
  printf '%s\n' \
    '    1     0 /sbin/launchd' \
    '  510     1 -zsh' \
    '  620   510 node   /Users/me/very long/start-v2.mjs  --x' \
    ' 6201   620 /bin/sleep 5' \
    '   62   510 node other.mjs'
}

PROC_ROOT=$WORK/no-proc
process_reader
assert_eq "$READER" ps
assert_eq "$(ps_command 620)" 'node   /Users/me/very long/start-v2.mjs  --x'
assert_eq "$(ps_children 510)" "620${NL}62"
assert_eq "$(ps_children 62)" ''

# "very long/start-v2.mjs" splits into words; the basename is still found.
assert_eq "$(detect_launcher 510)" start-v2.mjs
assert_eq "$(wc -l < "$PS_CALLS" | tr -d ' ')" 1
