# Sourced by the vscode-open-workspace cases, after harness.sh.
#
# The command runs as a child process, so powershell.exe, code and setsid are
# stand-ins on PATH rather than functions. PATH is the stand-ins, the few tools
# they use, and flock, and nothing else: on WSL the real powershell.exe and
# code are on the inherited PATH, and reaching the real code would open a VS
# Code window. flock is the real one, in a folder of its own so a case can
# leave it out.
#
#   FAKE_TITLES        window titles powershell.exe prints, one per line; it
#                      prints them with CRLF line ends, as Windows does
#   FAKE_CHECK_STATUS  powershell.exe's exit status
#   FAKE_CODE_STATUS   code's exit status
#   FAKE_GATE          when set, powershell.exe writes $CHECK_STARTED, then
#                      waits up to 5s for this file to exist before answering,
#                      and writes $CHECK_DONE after
#   FAKE_LINGER        powershell.exe or code: that stand-in leaves a sleep
#                      running with every descriptor it was given except
#                      stdout and stderr, and adds its pid to $LINGERING
#
# code writes its arguments to $CODE_LOG, and powershell.exe adds a line to
# $CHECK_LOG each time it runs, so a case asserts on what ran.
#
# setsid stands in for util-linux's: with -f it starts the program and returns
# at once, passing its stdin on; without it the program runs in its place, so
# the caller waits for it.
# It writes its arguments to $SETSID_LOG.

command -v flock > /dev/null 2>&1 || fail "flock is not installed, which this case and the command need"

FAKE_TITLES=''
FAKE_CHECK_STATUS=0
FAKE_CODE_STATUS=0
FAKE_GATE=''
FAKE_LINGER=''
CODE_LOG=$WORK/code.log
CHECK_LOG=$WORK/check.log
CHECK_STARTED=$WORK/check-started
CHECK_DONE=$WORK/check-done
SETSID_LOG=$WORK/setsid.log
LINGERING=$WORK/lingering
OPEN_LOG=$WORK/open.log

FLOCKBIN=$WORK/flockbin
mkdir -p "$FLOCKBIN"
ln -s "$(command -v flock)" "$FLOCKBIN/flock"

STANDINS=$WORK/standins
mkdir -p "$STANDINS"
ln -s "$(command -v awk)" "$STANDINS/awk"
ln -s "$(command -v sleep)" "$STANDINS/sleep"
cat > "$STANDINS/powershell.exe" <<'SHIM'
#!/bin/sh
echo check >> "$CHECK_LOG"
if [ "$FAKE_LINGER" = powershell.exe ]; then
  sleep 30 > /dev/null 2>&1 &
  echo "$!" >> "$LINGERING"
fi
if [ -n "$FAKE_GATE" ]; then
  echo started > "$CHECK_STARTED"
  n=0
  while [ ! -e "$FAKE_GATE" ] && [ "$n" -lt 50 ]; do
    sleep 0.1
    n=$((n + 1))
  done
fi
[ -n "$FAKE_TITLES" ] && printf '%s\n' "$FAKE_TITLES" | awk '{ printf "%s\r\n", $0 }'
[ -n "$FAKE_GATE" ] && echo done > "$CHECK_DONE"
exit "$FAKE_CHECK_STATUS"
SHIM
cat > "$STANDINS/code" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >> "$CODE_LOG"
if [ "$FAKE_LINGER" = code ]; then
  sleep 30 > /dev/null 2>&1 &
  echo "$!" >> "$LINGERING"
fi
exit "$FAKE_CODE_STATUS"
SHIM
cat > "$STANDINS/setsid" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >> "$SETSID_LOG"
if [ "$1" = -f ]; then
  shift
  # A bare & would give the program /dev/null as stdin, as a non-interactive sh
  # does; util-linux's setsid -f passes its own stdin on.
  exec 3<&0
  "$@" <&3 3<&- &
  exit 0
fi
exec "$@"
SHIM
chmod +x "$STANDINS/powershell.exe" "$STANDINS/code" "$STANDINS/setsid"

export FAKE_TITLES FAKE_CHECK_STATUS FAKE_CODE_STATUS FAKE_GATE FAKE_LINGER \
  CODE_LOG CHECK_LOG CHECK_STARTED CHECK_DONE SETSID_LOG LINGERING

# Runs the command; its stderr goes to $WORK/stderr and its exit status to
# OPEN_STATUS. run_open_workspace runs the detached copy's part in the
# foreground, so a case can assert on what it did once it returns;
# run_first_call runs it the way the hook does.
run_open_workspace() { # <name> <workspace-file>
  : > "$CODE_LOG"
  : > "$CHECK_LOG"
  PATH=$STANDINS:$FLOCKBIN VSCODE_OPEN_WORKSPACE_DETACHED=1 \
    VSCODE_OPEN_WORKSPACE_LOG=$OPEN_LOG \
    /bin/sh "$REPO/home/wsl/bin/vscode-open-workspace" "$@" 2> "$WORK/stderr"
  OPEN_STATUS=$?
}

run_first_call() { # <name> <workspace-file>
  : > "$CODE_LOG"
  : > "$CHECK_LOG"
  PATH=$STANDINS:$FLOCKBIN VSCODE_OPEN_WORKSPACE_LOG=$OPEN_LOG \
    /bin/sh "$REPO/home/wsl/bin/vscode-open-workspace" "$@" 2> "$WORK/stderr"
  OPEN_STATUS=$?
}

code_ran_with() {
  cat "$CODE_LOG"
}

checks_run() {
  wc -l < "$CHECK_LOG" | tr -d ' '
}

# Waits up to 5s for a file to have content.
wait_for() { # <file>
  n=0
  while [ ! -s "$1" ] && [ "$n" -lt 50 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  [ -s "$1" ]
}

lock_is_free() { # <workspace-file>
  flock -n "$1.lock" true
}

# Holds a workspace's lock from another process until killed; its pid is in
# HOLDER. Its sleep has the descriptor closed, so only the holder holds it.
hold_lock() { # <workspace-file>
  rm -f "$WORK/holder"
  sh -c 'exec 9>> "$1.lock"; flock -n 9 || exit 1; echo "$$" > "$2"; sleep 30 9>&- & wait $!' \
    sh "$1" "$WORK/holder" > /dev/null 2>&1 &
  wait_for "$WORK/holder" || fail "the holder never took the lock on $1"
  HOLDER=$(cat "$WORK/holder")
}

# Ends whatever a stand-in left running.
end_lingering() {
  [ -f "$LINGERING" ] || return 0
  while read -r pid; do
    kill "$pid" 2> /dev/null
  done < "$LINGERING"
  rm -f "$LINGERING"
}
