# Sourced by a case, inside the container. Everything here runs the real tmux
# and the real command, on a server labelled t.

CMD=/repo/home/common/bin/tmux-snapshot
L=t
export HOME=/work/home
export XDG_DATA_HOME=/work/data
SNAP=$XDG_DATA_HOME/tmux/snapshot/$L
mkdir -p "$HOME" "$XDG_DATA_HOME" /work/a /work/b /work/c

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
ok() { printf '  ok   %s\n' "$1"; }

# tmux on the test server, with no config.
tm() { tmux -L "$L" -f /dev/null "$@"; }

# Runs the command, showing what it printed, indented.
run() {
  printf -- '--- tmux-snapshot %s ---\n' "$*"
  "$CMD" "$@" > /work/out 2>&1
  status=$?
  sed 's/^/  | /' /work/out
  return "$status"
}

# A session of 270x85, the size restore creates sessions at, so layouts compare
# exactly.
new_session() { # <name> <first window name> <cwd>
  tm new-session -d -s "$1" -x 270 -y 85 -n "$2" -c "$3"
}

session_id() { # <name>: the id of the session with exactly this name
  tm list-sessions -F '#{session_id}|#{session_name}' | while IFS='|' read -r id name; do
    [ "$name" = "$1" ] && { printf '%s' "$id"; break; }
  done
}

# What a restore has to reproduce, one line per pane, in a stable order. The
# session name is bracketed so an empty one shows. A layout string holds its
# panes' ids and a checksum over them, and a new server numbers its panes
# afresh, so both are cut out; the geometry left is compared exactly, and each
# pane's own size and place besides.
state() {
  tm list-panes -a -F '[#{session_name}] #{window_index} #{window_name} panes=#{window_panes} #{pane_index} #{pane_current_path} #{pane_width}x#{pane_height}+#{pane_left}+#{pane_top} #{window_layout} title=#{@title} colour=#{@colour} state=#{@state} role=#{@role} status=#{@status}' |
    sed -E 's/ [0-9a-f]{4},([0-9]+x[0-9]+)/ \1/; s/([0-9]+x[0-9]+,[0-9]+,[0-9]+),[0-9]+/\1/g' | sort
}

# Waits for every pane's shell to have reached its cwd, which tmux reports
# from the process, so a save straight after a split can see the old one.
settle() { sleep 1; }

same_state() { # <expected> <what>
  actual=$(state)
  if [ "$actual" != "$1" ]; then
    printf 'expected:\n%s\nactual:\n%s\n' "$1" "$actual" | sed 's/^/    /'
    fail "$2"
  fi
  ok "$2"
}

files_digest() { # <dir>: names and checksums of everything in it
  ( cd "$1" 2>/dev/null && for f in * .[!.]*; do [ -f "$f" ] && cksum "$f"; done ) | sort
}
