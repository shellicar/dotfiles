#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "the run lock refuses a second command, takes over a dead one's, and is gone after every exit"

# Each command here is its own shell process, because the lock is about
# processes: its pid, kill -0 on it, and the traps that release it. git is a
# function in each that answers only what the lock needs, so nothing reaches
# a real repository.
LOCK=$WORK/git/cleanup-cache/lock

# run_as <command name> <script>: a shell that sources the library, takes the
# lock as that command, then runs the script. Its stderr goes to $WORK/err.
run_as() {
  sh -c '
    git() {
      case "$*" in
        --version) echo "git version 2.55.0" ;;
        "rev-parse --git-common-dir") echo "$WORK/git" ;;
        *) echo "unexpected: git $*" >&2; return 1 ;;
      esac
    }
    TOOL=$1
    . "$REPO/home/common/lib/git-common.sh"
    use_cache_dir
    eval "$2"
  ' sh "$1" "$2" 2> "$WORK/err"
}
export WORK REPO

# A normal exit releases it.
run_as 'git refresh' 'exit 0'
assert_eq "$?" 0
[ -e "$LOCK" ] && fail "the lock survived a normal exit"

# The merge check's stop is a TERM to the command's own shell.
run_as 'git refresh' 'kill "$$"; sleep 5'
assert_eq "$?" 143
[ -e "$LOCK" ] && fail "the lock survived the stop on a merge-tree error"

# Ctrl-C.
run_as 'git refresh' 'kill -INT "$$"; sleep 5'
assert_eq "$?" 130
[ -e "$LOCK" ] && fail "the lock survived Ctrl-C"

# A live holder: a command that waits, holding the lock, while a second starts.
run_as 'git refresh' 'echo "$$" > "$WORK/holder"; sleep 30 & echo $! > "$WORK/holder-sleep"; wait $!' > /dev/null &
bg=$!
i=0
while [ ! -s "$WORK/holder" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
holder=$(cat "$WORK/holder")

run_as 'git spread' 'exit 0'
assert_eq "$?" 1
assert_eq "$(cat "$WORK/err")" "git spread: git refresh (pid $holder) is already running in this repo"
assert_eq "$(cat "$LOCK/pid")" "$holder"
assert_eq "$(cat "$LOCK/command")" "git refresh"

kill "$holder"
wait "$bg" 2>/dev/null
# The holder's sleep outlives it: a TERM ends the shell, not its child.
kill "$(cat "$WORK/holder-sleep")" 2>/dev/null
[ -e "$LOCK" ] && fail "the holder's lock survived its TERM"

# A lock left by a process that died without its trap running.
sh -c 'exit 0' &
dead=$!
wait "$dead"
mkdir -p "$LOCK"
echo "$dead" > "$LOCK/pid"
echo 'git cleanup' > "$LOCK/command"

run_as 'git catchup' 'cat "$RUN_LOCK/pid" > "$WORK/taker"; echo "$$" > "$WORK/taker-pid"'
assert_eq "$?" 0
assert_eq "$(cat "$WORK/err")" "git catchup: taking over the lock left by git cleanup (pid $dead), which is no longer running"
assert_eq "$(cat "$WORK/taker")" "$(cat "$WORK/taker-pid")"
[ -e "$LOCK" ] && fail "the lock taken over survived the taker's exit"
:
