#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-tmux.sh
. "$TESTS/fake-tmux.sh"

describe 'the /proc reader walks children of every thread and skips a process with a thread in state D'

guard_path
# shellcheck source=../../home/common/lib/tmux-snapshot.sh
. "$REPO/home/common/lib/tmux-snapshot.sh"

# A /proc laid out as Linux lays it out: stat per thread, children per thread,
# cmdline NUL-separated.
PROC_ROOT=$WORK/proc
proc() { # <pid> <comm> <state per thread...>
  local pid comm tid
  pid=$1 comm=$2
  shift 2
  tid=$pid
  for state in "$@"; do
    mkdir -p "$PROC_ROOT/$pid/task/$tid"
    printf '%s (%s) %s 1 1 1\n' "$tid" "$comm" "$state" > "$PROC_ROOT/$pid/task/$tid/stat"
    : > "$PROC_ROOT/$pid/task/$tid/children"
    tid=$((tid + 1))
  done
}
mkdir -p "$PROC_ROOT/self"
: > "$PROC_ROOT/self/stat"

# 10: the shell. Its second thread (11) has child 20. 20 runs the launcher, its
# comm holding ') D (' to catch a state read by splitting.
proc 10 zsh S S
printf '20 ' > "$PROC_ROOT/10/task/11/children"
printf 'zsh\000' > "$PROC_ROOT/10/cmdline"
proc 20 'a) D (b' S
printf 'node\000/x/start-v2.mjs\000--resume\000' > "$PROC_ROOT/20/cmdline"

process_reader
assert_eq "$READER" proc
assert_eq "$(proc_command 20)" 'node /x/start-v2.mjs --resume'
assert_eq "$(detect_launcher 10)" start-v2.mjs

# The same launcher with one thread stuck in D: its cmdline is not read.
proc 30 node S D
printf 'node\000/x/start-v2.mjs\000' > "$PROC_ROOT/30/cmdline"
printf '30' > "$PROC_ROOT/10/task/10/children"
: > "$PROC_ROOT/10/task/11/children"
assert_eq "$(proc_command 30)" ''
assert_eq "$(detect_launcher 10)" ''

# A process that has exited has no directory, and reads as nothing.
assert_eq "$(proc_command 99)" ''
