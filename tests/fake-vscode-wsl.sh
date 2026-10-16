# Sourced by the vscode-open-workspace cases, after harness.sh.
#
# The command runs as a child process, so powershell.exe and code are stand-ins
# on PATH rather than functions. PATH is the stand-ins plus /usr/bin:/bin and
# nothing else: on WSL the real powershell.exe and code are on the inherited
# PATH, and reaching the real code would open a VS Code window.
#
#   FAKE_TITLES        window titles powershell.exe prints, one per line; it
#                      prints them with CRLF line ends, as Windows does
#   FAKE_CHECK_STATUS  powershell.exe's exit status
#   FAKE_CODE_STATUS   code's exit status
#
# code writes its arguments to $CODE_LOG, so a case asserts on whether it ran.

FAKE_TITLES=''
FAKE_CHECK_STATUS=0
FAKE_CODE_STATUS=0
CODE_LOG=$WORK/code.log

STANDINS=$WORK/standins
mkdir -p "$STANDINS"
cat > "$STANDINS/powershell.exe" <<'SHIM'
#!/bin/sh
[ -n "$FAKE_TITLES" ] && printf '%s\n' "$FAKE_TITLES" | awk '{ printf "%s\r\n", $0 }'
exit "$FAKE_CHECK_STATUS"
SHIM
cat > "$STANDINS/code" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >> "$CODE_LOG"
exit "$FAKE_CODE_STATUS"
SHIM
chmod +x "$STANDINS/powershell.exe" "$STANDINS/code"

# Runs the command with the stand-ins; its stderr goes to $WORK/stderr and its
# exit status to OPEN_STATUS.
run_open_workspace() { # <name> <workspace-file>
  : > "$CODE_LOG"
  PATH=$STANDINS:/usr/bin:/bin \
    FAKE_TITLES=$FAKE_TITLES FAKE_CHECK_STATUS=$FAKE_CHECK_STATUS \
    FAKE_CODE_STATUS=$FAKE_CODE_STATUS CODE_LOG=$CODE_LOG \
    sh "$REPO/home/wsl/bin/vscode-open-workspace" "$@" 2> "$WORK/stderr"
  OPEN_STATUS=$?
}

code_ran_with() {
  cat "$CODE_LOG"
}
