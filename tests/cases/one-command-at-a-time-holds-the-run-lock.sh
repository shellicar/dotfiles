#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "the run lock refuses a second command while another holds it, and is free once the holder is gone"

# Each command here is its own shell process, because the lock is held by a
# process: flock on a descriptor of its shell, which the kernel releases when
# the process ends. git is a function in each that answers only what the lock
# needs, so nothing reaches a real repository. flock is the real one.
command -v flock >/dev/null 2>&1 || fail "flock is not installed, which this case and the commands need"

LOCK=$WORK/git/cleanup-cache/lock
export WORK REPO

# run_as <command name> <script>: a shell that sources the library, takes the
# lock as that command, then runs the script. Its stderr goes to $WORK/err.
run_as() {
  sh -c '
    git() {
      case "$*" in
        --version) echo "git version 2.55.0" ;;
        "rev-parse --path-format=absolute --git-common-dir") echo "$WORK/git" ;;
        *) echo "unexpected: git $*" >&2; return 1 ;;
      esac
    }
    TOOL=$1
    . "$REPO/home/common/lib/git-common.sh"
    use_cache_dir
    eval "$2"
  ' sh "$1" "$2" 2> "$WORK/err"
}

# start_holder <how it ends>: a git refresh that takes the lock and waits, in
# the background. Its sleep has the lock's descriptor closed, as the commands
# close it for anything that could outlive them, so only the holder holds it.
start_holder() {
  rm -f "$WORK/holder"
  run_as 'git refresh' 'echo "$$" > "$WORK/holder"; sleep 30 9>&- & wait $!' > /dev/null &
  i=0
  while [ ! -s "$WORK/holder" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  holder=$(cat "$WORK/holder")
}

# Free: a second command takes it, runs and exits 0.
assert_free() {
  run_as 'git spread' 'exit 0' || fail "the lock was still held $1: $(cat "$WORK/err")"
}

# A second command is refused while the first holds it, naming the lock and,
# as best it can, the holder.
start_holder
run_as 'git spread' 'exit 0'
assert_eq "$?" 1
assert_eq "$(cat "$WORK/err")" "git spread: another command is running in this repo (it holds $LOCK)
  last taken by git refresh (pid $holder), which may not be the one holding it now"

# Killed with SIGKILL, so no trap runs.
kill -9 "$holder"
sleep 0.2
assert_free 'after the holder was killed with SIGKILL'

# A normal exit.
run_as 'git refresh' 'exit 0'
assert_eq "$?" 0
assert_free 'after a normal exit'

# The stop on a merge-tree error is a TERM to the command's own shell.
run_as 'git refresh' 'kill "$$"; sleep 5'
assert_eq "$?" 143
assert_free 'after the stop on a merge-tree error'

# flock missing: refused before anything else, with how to install it. PATH
# holds only mkdir, which use_cache_dir needs before it looks for flock.
mkdir -p "$WORK/minbin"
ln -s "$(command -v mkdir)" "$WORK/minbin/mkdir"
sh -c '
  git() { case "$*" in --version) echo "git version 2.55.0" ;; *) echo "$WORK/git" ;; esac; }
  TOOL="git refresh"
  . "$REPO/home/common/lib/git-common.sh"
  PATH=$WORK/minbin
  use_cache_dir
  echo reached
' > "$WORK/out" 2> "$WORK/err"
status=$?
assert_eq "$status" 1
assert_eq "$(cat "$WORK/out")" ""
assert_eq "$(cat "$WORK/err")" "git refresh: needs flock, to run one command at a time per repository. On macOS: brew install flock"
:
