# Sourced by the vscode-open-workspace cases, after harness.sh.
#
# The command runs as a child process, so powershell.exe, code and setsid are
# stand-ins on PATH rather than functions. PATH is the stand-ins plus
# /usr/bin:/bin and nothing else: on WSL the real powershell.exe and code are on
# the inherited PATH, and reaching the real code would open a VS Code window.
#
#   FAKE_TITLES        window titles powershell.exe prints, one per line; it
#                      prints them with CRLF line ends, as Windows does
#   FAKE_CHECK_STATUS  powershell.exe's exit status
#   FAKE_CODE_STATUS   code's exit status
#   FAKE_GATE          when set, powershell.exe writes $CHECK_STARTED, then
#                      waits up to 5s for this file to exist before answering,
#                      and writes $CHECK_DONE after
#
# code writes its arguments to $CODE_LOG, and powershell.exe adds a line to
# $CHECK_LOG each time it runs, so a case asserts on what ran.
#
# setsid stands in for util-linux's: with -f it starts the program and returns
# at once; without it the program runs in its place, so the caller waits for it.
# It writes its arguments to $SETSID_LOG.

FAKE_TITLES=''
FAKE_CHECK_STATUS=0
FAKE_CODE_STATUS=0
FAKE_GATE=''
CODE_LOG=$WORK/code.log
CHECK_LOG=$WORK/check.log
CHECK_STARTED=$WORK/check-started
CHECK_DONE=$WORK/check-done
SETSID_LOG=$WORK/setsid.log
OPEN_LOG=$WORK/open.log

STANDINS=$WORK/standins
mkdir -p "$STANDINS"
cat > "$STANDINS/powershell.exe" <<'SHIM'
#!/bin/sh
echo check >> "$CHECK_LOG"
if [ -n "$FAKE_GATE" ]; then
  : > "$CHECK_STARTED"
  n=0
  while [ ! -e "$FAKE_GATE" ] && [ "$n" -lt 50 ]; do
    sleep 0.1
    n=$((n + 1))
  done
fi
[ -n "$FAKE_TITLES" ] && printf '%s\n' "$FAKE_TITLES" | awk '{ printf "%s\r\n", $0 }'
[ -n "$FAKE_GATE" ] && : > "$CHECK_DONE"
exit "$FAKE_CHECK_STATUS"
SHIM
cat > "$STANDINS/code" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >> "$CODE_LOG"
exit "$FAKE_CODE_STATUS"
SHIM
cat > "$STANDINS/setsid" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >> "$SETSID_LOG"
if [ "$1" = -f ]; then
  shift
  "$@" &
  exit 0
fi
exec "$@"
SHIM
chmod +x "$STANDINS/powershell.exe" "$STANDINS/code" "$STANDINS/setsid"

export FAKE_TITLES FAKE_CHECK_STATUS FAKE_CODE_STATUS FAKE_GATE CODE_LOG \
  CHECK_LOG CHECK_STARTED CHECK_DONE SETSID_LOG

# Runs the command; its stderr goes to $WORK/stderr and its exit status to
# OPEN_STATUS. run_open_workspace runs the detached copy's part in the
# foreground, so a case can assert on what it did once it returns;
# run_first_call runs it the way the hook does.
run_open_workspace() { # <name> <workspace-file>
  : > "$CODE_LOG"
  : > "$CHECK_LOG"
  PATH=$STANDINS:/usr/bin:/bin VSCODE_OPEN_WORKSPACE_DETACHED=1 \
    VSCODE_OPEN_WORKSPACE_LOG=$OPEN_LOG \
    sh "$REPO/home/wsl/bin/vscode-open-workspace" "$@" 2> "$WORK/stderr"
  OPEN_STATUS=$?
}

run_first_call() { # <name> <workspace-file>
  : > "$CODE_LOG"
  : > "$CHECK_LOG"
  PATH=$STANDINS:/usr/bin:/bin VSCODE_OPEN_WORKSPACE_LOG=$OPEN_LOG \
    sh "$REPO/home/wsl/bin/vscode-open-workspace" "$@" 2> "$WORK/stderr"
  OPEN_STATUS=$?
}

code_ran_with() {
  cat "$CODE_LOG"
}

checks_run() {
  wc -l < "$CHECK_LOG" | tr -d ' '
}

# Waits up to 5s for a file to exist.
wait_for() { # <file>
  n=0
  while [ ! -e "$1" ] && [ "$n" -lt 50 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  [ -e "$1" ]
}

# A pid that belonged to a process which has exited.
dead_pid() {
  sh -c 'exit 0' &
  pid=$!
  wait "$pid"
  printf '%s\n' "$pid"
}
