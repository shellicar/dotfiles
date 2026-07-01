#!/bin/sh
# Resolve the pane's foreground command name from the terminal foreground
# process group (TPGID) of the pane's shell, not a pgrep child scan.
#
# Why not pgrep: `pgrep -P <pane_pid>` intermittently returns nothing for a
# child that provably exists (observed empty 60/60 while the CLI was active,
# though `ps` listed the child the whole time). When it came back empty the
# script fell through to the login shell's own name (`-zsh`), and tmux redrew
# the status bar on that value once a second — the flicker between the real
# command and `-zsh` on any actively-working pane.
#
# TPGID names the tty's foreground process group leader directly, which is the
# process actually running in the pane. Names still come from argv[0] (ps
# comm), so a wrapper that sets argv[0] (e.g. claude-sdk-cli, really node) is
# reported by its argv[0] name rather than the underlying binary.
pane_pid="$1"
tpgid=$(ps -o tpgid= -p "$pane_pid" 2>/dev/null | tr -d ' ')
comm=""
if [ -n "$tpgid" ] && [ "$tpgid" -gt 0 ] 2>/dev/null; then
  comm=$(ps -o comm= -p "$tpgid" 2>/dev/null)
fi
# Fallback: no foreground group (e.g. -1) or it vanished — name the shell.
if [ -z "$comm" ]; then
  comm=$(ps -o comm= -p "$pane_pid" 2>/dev/null)
fi
echo "${comm##*/}"
