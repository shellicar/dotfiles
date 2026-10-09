#!/bin/sh
#
# tmux-snapshot's logic, sourced by home/common/bin/tmux-snapshot, which parses
# the arguments into LABEL, LABEL_SET, ALL and APPLY and calls tmux_snapshot_main.
#
# A snapshot records, per pane, the session/window/pane identity, the exact
# window layout, the cwd, the foreground command, an allowlisted launcher (when
# the pane is running one), and the five user options the status bar renders
# from. Restore is plan-then-execute: plan_restore computes every step against
# the live server into PLAN, and the dry run (describe_plan) and --apply
# (execute_plan) both read that same PLAN, so the preview cannot diverge from
# what runs.
#
# SESSION NAMES. A name is the key that matches a snapshot to the live server
# (ids are reassigned every time a server starts), and "" is a name tmux allows.
# So a name is never read as a line on its own: every tmux listing that carries
# one is formatted '#{session_id}<US>#{session_name}', which is never an empty
# line, and $(...) cannot strip it. A session is targeted by its id, looked up
# from the name, never by '=name' or 'name:'.
#
# Every tmux call names its server with -L and its target by id; nothing relies
# on the "current" pane, which follows focus.

# The variables below are read by the command and by the tests, which shellcheck
# cannot see from inside this file.
# shellcheck disable=SC2034

US=$(printf '\037') # field separator: cannot appear in tmux values
NL='
'
SNAP_HEADER='tmux-snapshot 2'
PARK=999999 # parking index for the throwaway window new-session spawns

# The launchers restore re-runs bare (no args): a pane whose process tree runs
# one of these .mjs scripts is relaunched by basename, since the script
# re-establishes its own per-session state. Everything else restores to a plain
# shell. Kept small so unrelated commands (a stray dev server, swe.mjs with its
# args) are never resurrected. Space-separated.
LAUNCHERS='start-v2.mjs'

# tmux keeps one socket per server here; the socket filename is the label.
SERVER_DIR=/tmp/tmux-$(id -u)
PROC_ROOT=/proc

# Colour only when stdout is a terminal, so piped output stays clean.
if [ -t 1 ]; then
  ESC=$(printf '\033')
  DIM="${ESC}[2m"; BOLD="${ESC}[1m"; RESET="${ESC}[0m"
else
  DIM=''; BOLD=''; RESET=''
fi

# The pane fields tmux is asked for on save, in order. pane_pid is last so a
# row never ends in an empty field.
PANE_FORMAT="#{session_name}$US#{window_index}$US#{window_name}$US#{window_layout}$US#{pane_index}$US#{pane_current_path}$US#{pane_current_command}$US#{@title}$US#{@colour}$US#{@state}$US#{@role}$US#{@status}$US#{pane_pid}"

note() { printf 'tmux-snapshot: %s\n' "$*" >&2; }

# Ends the command. Only call it from the command's own shell, not inside
# $(...), where it would end the subshell and nothing else.
die() { note "$*"; exit 1; }

# tmux bound to the server being worked on. stdin is closed so a tmux call
# inside a `while read` loop cannot consume the loop's input.
#
# -u because without it, and without a UTF-8 locale (a server started outside
# a login shell, say), tmux 3.7 prints US in a format as '_'. tmux 3.5 prints it
# as '\037' even with -u; has_separator turns that into an error rather than a
# snapshot of garbage.
ts_tmux() { tmux -u -L "$TS_LABEL" "$@" </dev/null; }

# Whether the first line of tmux's output holds US, as every line asked for
# with one must. Empty output passes: it is no server, not a bad one.
# TODO(claude): undecided: whether a tmux that escapes US (3.5) is supported.
# For now it is refused: a save fails and marks @snapshot-error, a restore or
# the status view stops, rather than decoding '\037' back, which a name could
# hold literally.
has_separator() { # <tmux output>
  case ${1%%"$NL"*} in
    '' | *"$US"*) return 0 ;;
  esac
  return 1
}

separator_error() {
  printf 'tmux printed the field separator as something else (%s); this tmux is not supported' "$(tmux -V 2>&1)"
}

# A session name for people to read: "" for the empty name, which otherwise
# prints as nothing at all.
# TODO(claude): undecided: how an empty session name is shown. Shown as "" for
# now, which a session literally named "" (two quote marks) also prints as.
show_name() {
  if [ -z "$1" ]; then printf '""'; else printf '%s' "$1"; fi
}

plural() { # <n> <word>
  if [ "$1" -eq 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %ss' "$1" "$2"; fi
}

# One line of fields separated by US.
us_line() {
  local IFS
  IFS=$US
  printf '%s\n' "$*"
}

# ── snapshot files ───────────────────────────────────────────────────────────
#
# Each server label has its own directory. Inside it, a double buffer: the new
# snapshot is written to a per-process temp, the current front is copied aside
# to previous.snap, then the temp is renamed over current.snap. current.snap is
# never absent or half-written once it exists.
#
# The format: the first line is SNAP_HEADER; the second is 'saved ' and the
# save time as local 'YYYY-MM-DD HH:MM' (no zone: reading a file's mtime, or
# formatting a stored epoch, takes different flags on GNU and BSD); then one
# pane per line, fields separated by US in the order parse_pane reads them. The
# last field, the pane's pid at save time, is never empty, so `read` never meets
# a line ending in a separator. It is recorded, not used.
# The JSON files an earlier version of this command wrote (current.json,
# previous.json, .writing.*.json) are never read, written, renamed or deleted.

snapshot_base() { printf '%s/tmux/snapshot' "${XDG_DATA_HOME:-$HOME/.local/share}"; }
snapshot_dir() { printf '%s/%s' "$(snapshot_base)" "$1"; }

SAVED_PATTERN='saved [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]'

# Whether a file is one this reads: the version line, then a saved line. A
# refusal names the file and what it found, and nothing else in the file is
# read. Pass quiet to say nothing.
snapshot_accepts() { # <file> [quiet]
  local first second
  first='' second=''
  { IFS= read -r first; IFS= read -r second; } < "$1" 2>/dev/null
  if [ "$first" = "$SNAP_HEADER" ]; then
    # shellcheck disable=SC2254 # the pattern is the point
    case $second in $SAVED_PATTERN) return 0 ;; esac
    [ "${2:-}" = quiet ] && return 1
    note "refusing $1: its second line is '$(printf '%.40s' "$second")'; expected 'saved YYYY-MM-DD HH:MM'"
    return 1
  fi
  [ "${2:-}" = quiet ] && return 1
  case $first in
    'tmux-snapshot '*) note "refusing $1: its version line is '$first'; this reads '$SNAP_HEADER'" ;;
    '') note "refusing $1: no version line (the first line is empty)" ;;
    *) note "refusing $1: no version line (the first line starts '$(printf '%.40s' "$first")')" ;;
  esac
  return 1
}

# The save time of an accepted snapshot file, as 'YYYY-MM-DD HH:MM'.
snapshot_saved() { # <file>
  sed -n '2s/^saved //p' "$1"
}

# The snapshot file to read for a label: current.snap, or previous.snap when
# current is missing or refused. Nothing when neither is readable.
snapshot_find() { # <label>
  local dir name
  dir=$(snapshot_dir "$1")
  for name in current.snap previous.snap; do
    [ -f "$dir/$name" ] || continue
    snapshot_accepts "$dir/$name" && { printf '%s' "$dir/$name"; return 0; }
  done
  return 1
}

# Pane lines ordered by session name, then numeric window index, then numeric
# pane index. Everything below that reads pane lines expects this order.
sort_panes() { LC_ALL=C sort -t "$US" -k1,1 -k2,2n -k5,5n; }

# The pane lines of an accepted snapshot file, without its first two lines.
snapshot_panes() { # <file>
  sed 1,2d "$1" | sort_panes
}

# Splits one pane line into P_* variables. Fails for a line with no window
# index, which no pane has: a blank line, or one that is not a pane.
parse_pane() { # <line>
  IFS=$US read -r P_SESSION P_WIDX P_WNAME P_LAYOUT P_PIDX P_PATH P_CMD P_LAUNCHER \
    P_TITLE P_COLOUR P_STATE P_ROLE P_STATUS P_PID <<EOF
$1
EOF
  [ -n "$P_WIDX" ]
}

# Writes a snapshot. On failure SAVE_ERROR says why and the temp is removed;
# on success SNAP_FILE is the file written.
snapshot_write() { # <label> <save time> <pane lines>
  local dir front back draw err
  dir=$(snapshot_dir "$1")
  front=$dir/current.snap
  back=$dir/previous.snap
  draw=$dir/.writing.$$.snap # per process, so concurrent saves never share it
  SAVE_ERROR=''
  if ! err=$(mkdir -p "$dir" 2>&1); then
    SAVE_ERROR="cannot create $dir: $err"
    return 1
  fi
  if ! err=$( (printf '%s\nsaved %s\n%s\n' "$SNAP_HEADER" "$2" "$3" > "$draw") 2>&1 ); then
    rm -f "$draw"
    SAVE_ERROR="cannot write $draw: $err"
    return 1
  fi
  # TODO(claude): undecided: what happens to a current.snap this does not read
  # (another version, or damaged). For now it is not copied over previous.snap,
  # which keeps the last good previous, and the new save replaces it.
  if [ -f "$front" ] && snapshot_accepts "$front" quiet; then
    if ! err=$(cp -p "$front" "$back" 2>&1); then
      rm -f "$draw"
      SAVE_ERROR="cannot copy $front to $back: $err"
      return 1
    fi
  fi
  if ! err=$(mv -f "$draw" "$front" 2>&1); then
    rm -f "$draw"
    SAVE_ERROR="cannot rename $draw to $front: $err"
    return 1
  fi
  SNAP_FILE=$front
}

# ── reading a snapshot ───────────────────────────────────────────────────────

# One line per window: session, window index, window name, pane count, in the
# order of the pane lines given. The name is the first pane's.
snapshot_windows() { # <sorted pane lines>
  local line key prev have n ws wi wn
  prev='' have=0 n=0
  while IFS= read -r line; do
    parse_pane "$line" || continue
    key=$P_SESSION$US$P_WIDX
    if [ "$have" = 1 ] && [ "$key" = "$prev" ]; then
      n=$((n + 1))
      continue
    fi
    [ "$have" = 1 ] && us_line "$ws" "$wi" "$wn" "$n"
    have=1 prev=$key n=1 ws=$P_SESSION wi=$P_WIDX wn=$P_WNAME
  done <<EOF
$1
EOF
  [ "$have" = 1 ] && us_line "$ws" "$wi" "$wn" "$n"
  return 0
}

# Prints the pane lines of one window.
window_panes() { # <sorted pane lines> <session> <window index>
  local line
  while IFS= read -r line; do
    parse_pane "$line" || continue
    [ "$P_SESSION" = "$2" ] && [ "$P_WIDX" = "$3" ] && printf '%s\n' "$line"
  done <<EOF
$1
EOF
  return 0
}

count_lines() {
  local line n
  n=0
  while IFS= read -r line; do
    [ -n "$line" ] && n=$((n + 1))
  done <<EOF
$1
EOF
  printf '%s' "$n"
}

# The number of distinct sessions in snapshot_windows output, which keeps a
# session's windows together. The first window always counts, whatever its
# session is called, "" included.
count_sessions() { # <windows>
  local ws wi wn wc prev started n
  started=0 n=0 prev=''
  while IFS=$US read -r ws wi wn wc; do
    [ -n "$wi" ] || continue
    if [ "$started" = 0 ] || [ "$ws" != "$prev" ]; then
      started=1 prev=$ws n=$((n + 1))
    fi
  done <<EOF
$1
EOF
  printf '%s' "$n"
}

# ── the live server ──────────────────────────────────────────────────────────

# '#{session_id}<US>#{session_name}' per session, so no line is empty.
live_sessions() { ts_tmux list-sessions -F "#{session_id}$US#{session_name}" 2>/dev/null; }
live_windows() { ts_tmux list-windows -a -F "#{session_id}$US#{window_index}" 2>/dev/null; }

# The id of the session with this exact name, from live_sessions output.
session_id_of() { # <name> <live sessions>
  local id name
  while IFS=$US read -r id name; do
    [ -n "$id" ] || continue
    [ "$name" = "$1" ] && { printf '%s' "$id"; return 0; }
  done <<EOF
$2
EOF
  return 1
}

window_exists() { # <session id> <window index> <live windows>
  local id idx
  while IFS=$US read -r id idx; do
    [ "$id" = "$1" ] && [ "$idx" = "$2" ] && return 0
  done <<EOF
$3
EOF
  return 1
}

# Whether a server answers on this label. Whether its socket exists says
# nothing: a dead server can leave its socket behind. Session ids are never
# empty, so a server whose only session is called "" still prints something.
server_running() { # <label>
  [ -n "$(tmux -u -L "$1" list-sessions -F '#{session_id}' 2>/dev/null </dev/null)" ]
}

# The labels of the servers whose sockets exist. A missing directory (no server
# ever started) lists none.
server_labels() {
  local f
  for f in "$SERVER_DIR"/* "$SERVER_DIR"/.[!.]* "$SERVER_DIR"/..?*; do
    [ -S "$f" ] && printf '%s\n' "${f##*/}"
  done
  return 0
}

# The labels that have a snapshot directory. Only directories: the base can also
# hold stray files, which are not labels.
snapshot_labels() {
  local d base
  base=$(snapshot_base)
  for d in "$base"/* "$base"/.[!.]* "$base"/..?*; do
    [ -d "$d" ] && printf '%s\n' "${d##*/}"
  done
  return 0
}

# Resolves the server to work on into TS_LABEL. -L names it; otherwise it is the
# one this pane is in, from $TMUX (socket,pid,session; the socket path can hold
# commas, so the fields are cut from the right).
#
# The orphan trap: if this pane's server was orphaned (its socket removed and a
# fresh server started on the same label), -L reaches that other server, and a
# bare command would silently work on the wrong one. $TMUX's pid is our real
# server's; display-message reports the pid the socket resolves to now. A
# mismatch means we are the orphan. An explicit -L is a deliberate target, so it
# is not checked.
resolve_target() {
  local rest socket envpid livepid
  if [ "$LABEL_SET" = 1 ]; then
    TS_LABEL=$LABEL
    return 0
  fi
  [ -n "${TMUX:-}" ] || die 'not inside a tmux server'
  rest=${TMUX%,*}
  envpid=${rest##*,}
  socket=${rest%,*}
  TS_LABEL=${socket##*/}
  livepid=$(ts_tmux display-message -p '#{pid}' 2>/dev/null)
  if [ "$livepid" != "$envpid" ]; then
    if [ -n "$livepid" ]; then livepid="pid $livepid"; else livepid=nothing; fi
    die "this pane belongs to an orphaned '$TS_LABEL' server (pid $envpid); the '$TS_LABEL' socket now points at $livepid. Run from a live pane, or target it explicitly with -L."
  fi
}

# ── launcher detection ───────────────────────────────────────────────────────
#
# A pane's foreground is often a `node <script>` wrapper, so the launcher is a
# descendant: the pane's whole process tree is walked, not one level of
# children, which misses it. A reader supplies two facts per process,
# <reader>_command and <reader>_children, and only the reader is
# platform-specific. Args are dropped: restore re-runs the launcher bare.

# Picks the reader once per save: /proc where there is one, otherwise one ps for
# the whole machine. The probe is /proc itself, not the OS, since what the
# reader needs is those files and a Mac has none of them.
process_reader() {
  if [ -r "$PROC_ROOT/self/stat" ]; then
    READER='proc'
  else
    READER='ps'
    # One ps per save, however many panes. -ww so no command line is cut to a
    # width, which could drop a long launcher path's .mjs. A failing ps leaves
    # what it printed: launchers it missed are not detected.
    # TODO(claude): untested on macOS. On a Mac, check that
    #   ps -axo pid=,ppid=,command= -ww | awk '{ print length }' | sort -n | tail -1
    # shows uncut lines, and that a launcher with a long path is still detected.
    PS_TABLE=$(ps -ww -axo pid=,ppid=,command= 2>/dev/null)
  fi
}

# Linux: read /proc directly, and skip any process with a thread in state D.
# Reading a cmdline takes the target's mmap lock, so it blocks for as long as a
# thread stuck in the kernel holds that lock. ps reads every process's cmdline
# whenever its format includes a command-name field, whatever -p selects, so one
# stuck process anywhere blocks it, which is why Linux does not use ps. stat and
# children take no such lock, so a wedged pane costs its own launcher only.
# Every thread is checked, because /proc/<pid>/stat reports the main thread
# alone and the thread holding the lock can be any of them.
proc_command() { # <pid>
  local t stat state
  for t in "$PROC_ROOT/$1"/task/*; do
    [ -r "$t/stat" ] || continue
    stat=$(cat "$t/stat" 2>/dev/null)
    # The second field is comm in parens and may itself hold spaces and parens,
    # so the state is read from after the last ')', never by splitting.
    state=${stat##*") "}
    state=${state%% *}
    [ "$state" = D ] && return 0
  done
  [ -r "$PROC_ROOT/$1/cmdline" ] || return 0
  tr '\000' ' ' < "$PROC_ROOT/$1/cmdline" 2>/dev/null | sed 's/^ *//; s/ *$//'
}

proc_children() { # <pid>
  cat "$PROC_ROOT/$1"/task/*/children 2>/dev/null
  return 0
}

# ps prints ppid before the command, and a command contains spaces, so the
# first two fields are cut off and the rest kept whole.
ps_command() { # <pid>
  printf '%s\n' "$PS_TABLE" | awk -v p="$1" '
    $1 == p { s = $0; sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]*/, "", s); print s; exit }'
}

ps_children() { # <pid>
  printf '%s\n' "$PS_TABLE" | awk -v p="$1" '$2 == p { print $1 }'
}

# Each process's command in the tree under a pid, one per line, breadth first.
walk_tree() { # <pid>
  local queue pid seen cmd
  queue=$1 seen=' '
  while :; do
    # shellcheck disable=SC2086 # the queue is pids, split on purpose
    set -- $queue
    [ "$#" -gt 0 ] || break
    pid=$1
    shift
    queue=$*
    case $pid in '' | *[!0-9]*) continue ;; esac
    # A pid cannot be its own ancestor, but never loop on a malformed tree.
    case $seen in *" $pid "*) continue ;; esac
    seen="$seen$pid "
    cmd=$("${READER}_command" "$pid")
    [ -n "$cmd" ] && printf '%s\n' "$cmd"
    queue="$queue $("${READER}_children" "$pid")"
  done
  return 0
}

# The allowlisted launcher in a pane's process tree, or nothing. In each
# command, the first word whose basename ends in .mjs is its script; the first
# script in LAUNCHERS wins.
detect_launcher() { # <pane pid>
  walk_tree "$1" | (
    set -f
    while IFS= read -r cmd; do
      script=''
      for word in $cmd; do
        case ${word##*/} in *.mjs) script=${word##*/}; break ;; esac
      done
      [ -n "$script" ] || continue
      case " $LAUNCHERS " in *" $script "*) printf '%s' "$script"; exit 0 ;; esac
    done
  )
}

# ── save ─────────────────────────────────────────────────────────────────────

# Turns list-panes rows into pane lines, detecting each pane's launcher.
panes_from_rows() { # <list-panes rows>
  local session widx wname layout pidx path cmd title colour state role status pid launcher
  while IFS=$US read -r session widx wname layout pidx path cmd title colour state role status pid; do
    [ -n "$widx" ] || continue
    launcher=$(detect_launcher "$pid")
    us_line "$session" "$widx" "$wname" "$layout" "$pidx" "$path" "$cmd" "$launcher" \
      "$title" "$colour" "$state" "$role" "$status" "$pid"
  done <<EOF
$1
EOF
}

# A readable tree of what was captured: session, window, panes, each pane with
# its process and cwd.
summarize() { # <sorted pane lines>
  local windows ws wi wn wc prev started line
  windows=$(snapshot_windows "$1")
  started=0 prev=''
  while IFS=$US read -r ws wi wn wc; do
    [ -n "$wi" ] || continue
    if [ "$started" = 0 ] || [ "$ws" != "$prev" ]; then
      started=1 prev=$ws
      printf '%s\n' "$(show_name "$ws")"
    fi
    printf '  %s  %s  (%s)\n' "$wi" "$wn" "$(plural "$wc" pane)"
    while IFS= read -r line; do
      parse_pane "$line" || continue
      if [ -n "$P_LAUNCHER" ]; then
        printf '       %s  %-15s %s  (launcher: %s)\n' "$P_PIDX" "$P_CMD" "$P_PATH" "$P_LAUNCHER"
      else
        printf '       %s  %-15s %s\n' "$P_PIDX" "$P_CMD" "$P_PATH"
      fi
    done <<EOF
$(window_panes "$1" "$ws" "$wi")
EOF
  done <<EOF
$windows
EOF
}

# Records a failed save on the server it was for, where the status bar shows it
# and `tmux show -gv @snapshot-error` prints it.
save_failed() { # <message>
  note "save failed: $1"
  ts_tmux set-option -g @snapshot-error "$1" 2>/dev/null
  return 1
}

save_server() {
  local raw panes
  # A stale socket (file present, server dead) makes list-panes fail; a live
  # server always has a pane, so no output means no server.
  raw=$(ts_tmux list-panes -a -F "$PANE_FORMAT" 2>/dev/null)
  if [ -z "$raw" ]; then
    note "no server running on '$TS_LABEL', nothing to save"
    return 0
  fi

  # A lone pane is an empty server just started, or a crash that left nothing.
  # Saving it would overwrite the last good snapshot with nothing worth
  # restoring. Not a failure: @snapshot-error is left as it is.
  if [ "$(count_lines "$raw")" -eq 1 ]; then
    note "server '$TS_LABEL' has a single pane (fresh/empty), not saving"
    return 0
  fi

  has_separator "$raw" || { save_failed "$(separator_error)"; return 1; }

  note "saving server '$TS_LABEL'"
  process_reader
  panes=$(panes_from_rows "$raw" | sort_panes)
  snapshot_write "$TS_LABEL" "$(date '+%Y-%m-%d %H:%M')" "$panes" || { save_failed "$SAVE_ERROR"; return 1; }
  ts_tmux set-option -gu @snapshot-error 2>/dev/null
  summarize "$panes"
  note "wrote $(count_lines "$panes") panes to $SNAP_FILE"
}

cmd_save() {
  local servers label failed
  if [ "$ALL" = 1 ]; then
    [ "$LABEL_SET" = 1 ] && die 'cannot combine -a with -L'
    servers=$(server_labels)
    [ -n "$servers" ] || die 'no tmux servers found'
    failed=0
    # TODO(claude): undecided: whether one server's failed save stops -a. For
    # now the others are still saved and the command exits 1 at the end.
    while IFS= read -r label; do
      [ -n "$label" ] || continue
      TS_LABEL=$label
      save_server || failed=1
    done <<EOF
$servers
EOF
    return "$failed"
  fi
  resolve_target
  save_server
}

# ── restore ──────────────────────────────────────────────────────────────────
#
# PLAN is one step per line, fields separated by US, the first naming the step:
#
#   create-session  name
#   create-window   session name, window index, window name, pane count
#   skip-window     session name, window index
#
# Sessions first, then the windows to create, then the windows that exist. A
# session in the snapshot that exists on the server is not created; a window
# whose session exists and has that index is skipped.

plan_restore() { # <sorted pane lines> <live sessions> <live windows>
  local windows ws wi wn wc prev started sid sessions creates skips
  windows=$(snapshot_windows "$1")
  started=0 prev='' sid='' sessions='' creates='' skips=''
  while IFS=$US read -r ws wi wn wc; do
    [ -n "$wi" ] || continue
    # The first window starts a session whatever its name, "" included.
    if [ "$started" = 0 ] || [ "$ws" != "$prev" ]; then
      started=1 prev=$ws
      sid=$(session_id_of "$ws" "$2") || sessions=$sessions$(us_line create-session "$ws")$NL
    fi
    if [ -n "$sid" ] && window_exists "$sid" "$wi" "$3"; then
      skips=$skips$(us_line skip-window "$ws" "$wi")$NL
    else
      creates=$creates$(us_line create-window "$ws" "$wi" "$wn" "$wc")$NL
    fi
  done <<EOF
$windows
EOF
  PLAN=$sessions$creates$skips
}

plan_for_server() { # <sorted pane lines>
  local sessions windows
  sessions=$(live_sessions)
  windows=$(live_windows)
  { has_separator "$sessions" && has_separator "$windows"; } || die "$(separator_error)"
  plan_restore "$1" "$sessions" "$windows"
}

plan_count() { # <step name>
  local action rest n
  n=0
  while IFS=$US read -r action rest; do
    [ "$action" = "$1" ] && n=$((n + 1))
  done <<EOF
$PLAN
EOF
  printf '%s' "$n"
}

describe_plan() { # <sorted pane lines>
  local action a b c d line
  while IFS=$US read -r action a b c d; do
    case $action in
      create-session)
        printf 'create session: %s\n' "$(show_name "$a")" ;;
      create-window)
        printf 'create window: %s%s:%s%s "%s" (%s)\n' "$BOLD" "$(show_name "$a")" "$b" "$RESET" "$c" "$(plural "$d" pane)"
        while IFS= read -r line; do
          parse_pane "$line" || continue
          if [ -e "$P_PATH" ]; then
            printf '    pane %s: cwd=%s\n' "$P_PIDX" "$P_PATH"
            [ -n "$P_LAUNCHER" ] && printf '      %srun:%s %s%s%s\n' "$DIM" "$RESET" "$BOLD" "$P_LAUNCHER" "$RESET"
          else
            printf '    pane %s: cwd=%s%s (missing, opens in ~)%s\n' "$P_PIDX" "$P_PATH" "$DIM" "$RESET"
            [ -n "$P_LAUNCHER" ] && printf '      %sskip %s: dir missing%s\n' "$DIM" "$P_LAUNCHER" "$RESET"
          fi
        done <<EOF
$(window_panes "$1" "$a" "$b")
EOF
        ;;
      skip-window)
        printf '%sskip window: %s:%s (exists)%s\n' "$DIM" "$(show_name "$a")" "$b" "$RESET" ;;
    esac
  done <<EOF
$PLAN
EOF
}

# Runs a tmux command and ends the restore when it fails. tmux's own message
# has already gone to stderr.
must() {
  ts_tmux "$@" && return 0
  die "restore stopped: tmux $1 failed"
}

execute_plan() { # <sorted pane lines>
  local live action a b c d out sid park parks wid pane first line launches path launcher
  live=$(live_sessions)
  parks='' launches=''

  # Every target below is an id. '=' followed by an empty session name is
  # tmux's mouse target, and a name may hold ':' or '.'.
  while IFS=$US read -r action a b c d; do
    case $action in
      create-session)
        # Created detached. The window new-session spawns is parked out of the
        # way of the saved indexes, and killed once the session has its real
        # windows: killing it sooner would take the session with it and fire
        # session-closed.
        out=$(ts_tmux new-session -d -s "$a" -x 270 -y 85 -P -F "#{session_id}$US#{window_id}") ||
          die "restore stopped: cannot create session $(show_name "$a")"
        sid=${out%%"$US"*}
        park=${out#*"$US"}
        must move-window -s "$park" -t "$sid:$PARK"
        live="$live$NL$sid$US$a"
        parks="$parks $park"
        ;;
      create-window)
        sid=$(session_id_of "$a" "$live") || die "restore stopped: no session $(show_name "$a") for window $b"
        first=1
        # The first pane comes from new-window, the rest from split-window, and
        # the saved layout is re-applied after every one. Applying it once at
        # the end cannot work: each unguided split halves the room the panes
        # already have, so they shrink until a split has nowhere to go.
        # Re-applying spreads what exists over the whole window each time; tmux
        # drops the cells it has no pane for yet, and only refuses the reverse.
        #
        # -f splits the whole window. Without it tmux splits the active pane,
        # which the re-applied layout can have put in a one-row cell, and a
        # one-row pane cannot be split. -f also always adds the new pane last,
        # so pane N is created with saved pane N's cwd. Panes are created even
        # when their cwd is gone (tmux falls back to HOME), so the pane count
        # matches the layout.
        while IFS= read -r line; do
          parse_pane "$line" || continue
          if [ "$first" = 1 ]; then
            out=$(ts_tmux new-window -t "$sid:$b" -n "$c" -c "$P_PATH" -P -F "#{window_id}$US#{pane_id}") ||
              die "restore stopped: cannot create window $(show_name "$a"):$b"
            wid=${out%%"$US"*}
            pane=${out#*"$US"}
            # Window-scope labels, shared by the window's panes, from the first.
            [ -n "$P_TITLE" ] && must set-option -w -t "$wid" @title "$P_TITLE"
            [ -n "$P_COLOUR" ] && must set-option -w -t "$wid" @colour "$P_COLOUR"
            [ -n "$P_STATE" ] && must set-option -w -t "$wid" @state "$P_STATE"
            first=0
          else
            pane=$(ts_tmux split-window -f -t "$wid" -c "$P_PATH" -P -F '#{pane_id}') ||
              die "restore stopped: cannot add pane $P_PIDX to window $(show_name "$a"):$b"
          fi
          must select-layout -t "$wid" "$P_LAYOUT"
          [ -n "$P_ROLE" ] && must set-option -p -t "$pane" @role "$P_ROLE"
          [ -n "$P_STATUS" ] && must set-option -p -t "$pane" @status "$P_STATUS"
          [ -n "$P_LAUNCHER" ] && launches="$launches$pane$US$P_PATH$US$P_LAUNCHER$NL"
        done <<EOF
$(window_panes "$1" "$a" "$b")
EOF
        ;;
    esac
  done <<EOF
$PLAN
EOF

  # Launchers run once the layout is built, and only where the saved cwd still
  # exists: a missing one put the pane in HOME, and starting the launcher there
  # is worse than leaving a plain shell.
  while IFS=$US read -r pane path launcher; do
    [ -n "$pane" ] || continue
    [ -e "$path" ] || continue
    must send-keys -t "$pane" -l "$launcher"
    must send-keys -t "$pane" Enter
  done <<EOF
$launches
EOF

  for park in $parks; do
    ts_tmux kill-window -t "$park" 2>/dev/null
  done
  return 0
}

cmd_restore() {
  local file panes
  [ "$ALL" = 1 ] && die '-a is not supported for restore (single server only)'
  resolve_target
  note "restoring server '$TS_LABEL'"
  file=$(snapshot_find "$TS_LABEL") || die "no snapshot for '$TS_LABEL' in $(snapshot_dir "$TS_LABEL")"
  panes=$(snapshot_panes "$file")
  plan_for_server "$panes"

  if [ "$APPLY" != 1 ]; then
    printf 'DRY RUN: no changes will be made (pass --apply to commit)\n'
    describe_plan "$panes"
    note "would create $(plan_count create-session) session(s), $(plan_count create-window) window(s); skip $(plan_count skip-window) existing"
    return 0
  fi

  execute_plan "$panes"
  note "restore complete from $file: created $(plan_count create-window) window(s), skipped $(plan_count skip-window)"
}

# ── status ───────────────────────────────────────────────────────────────────
#
# The bare command answers "what can I restore, and would it do anything?". The
# rows are the union of the labels holding a snapshot and the servers running
# now: a running server with no snapshot is one nothing is protecting, and a
# snapshot with no server is one waiting to be restored. The restore column
# comes from plan_restore, so it cannot promise work restore would not do.

MONTHS='Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'

# The save time as precisely as helps: the clock for today, the date for
# anything older, the year once it is not this one. Takes 'YYYY-MM-DD HH:MM'.
when() { # <saved> [today as YYYY-MM-DD]
  local d t y m day today
  case $1 in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' '[0-9][0-9]:[0-9][0-9]) ;;
    *) printf '?'; return 0 ;;
  esac
  today=${2:-$(date +%Y-%m-%d)}
  d=${1%% *} t=${1#* }
  [ "$d" = "$today" ] && { printf 'today %s' "$t"; return 0; }
  y=${d%%-*}
  m=${d#*-} m=${m%-*}
  day=${d##*-} day=${day#0}
  case $m in 0[1-9] | 1[0-2]) ;; *) printf '?'; return 0 ;; esac
  # shellcheck disable=SC2086 # the month names, split on purpose
  set -- $MONTHS
  shift $((${m#0} - 1))
  if [ "$y" = "${today%%-*}" ]; then
    printf '%s %s %s' "$day" "$1" "$t"
  else
    printf '%s %s %s' "$day" "$1" "$y"
  fi
}

# One US-separated row per label: label, saved, sessions, windows, panes,
# server, restore.
status_rows() {
  local label labels running file panes windows saved todo n
  labels=$( { snapshot_labels; server_labels; } | LC_ALL=C sort -u)
  while IFS= read -r label; do
    [ -n "$label" ] || continue
    TS_LABEL=$label
    running=-
    server_running "$label" && running=running
    if ! file=$(snapshot_find "$label"); then
      # Neither a snapshot nor a server is a leftover directory, not a row.
      [ "$running" = running ] && us_line "$label" - - - - running 'no snapshot'
      continue
    fi
    panes=$(snapshot_panes "$file")
    windows=$(snapshot_windows "$panes")
    if [ "$running" = running ]; then
      plan_for_server "$panes"
    else
      plan_restore "$panes" '' ''
    fi
    todo=''
    n=$(plan_count create-session)
    [ "$n" -gt 0 ] && todo=$(plural "$n" session)
    n=$(plan_count create-window)
    [ "$n" -gt 0 ] && todo="${todo:+$todo, }$(plural "$n" window)"
    saved=$(when "$(snapshot_saved "$file")")
    us_line "$label" "$saved" "$(count_sessions "$windows")" "$(count_lines "$windows")" \
      "$(count_lines "$panes")" "$running" "${todo:-up to date}"
  done <<EOF
$labels
EOF
}

# Columns sized to their contents, counts right-aligned so they read as numbers.
# The header is dimmed after padding, since escape codes are not printed width.
render_table() { # <rows>
  { us_line label saved sessions windows panes server restore; printf '%s\n' "$1"; } |
    awk -F "$US" -v dim="$DIM" -v reset="$RESET" '
      {
        for (i = 1; i <= NF; i++) { cell[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) }
        if (NF > nf) nf = NF
        n = NR
      }
      END {
        for (r = 1; r <= n; r++) {
          line = ""
          for (i = 1; i <= nf; i++) {
            c = cell[r, i]
            pad = ""
            for (k = length(c); k < w[i]; k++) pad = pad " "
            if (i >= 3 && i <= 5) c = pad c; else c = c pad
            line = line (i > 1 ? "  " : "") c
          }
          sub(/ +$/, "", line)
          if (r == 1) line = dim line reset
          print line
        }
      }'
}

usage_lines() {
  printf '%s\n' \
    'usage: tmux-snapshot [-L label | -a] save' \
    '       tmux-snapshot [-L label] restore [--apply]' \
    '       tmux-snapshot restore-server <label> [--apply]'
}

cmd_status() {
  local rows
  rows=$(status_rows)
  if [ -n "$rows" ]; then
    render_table "$rows"
    printf '\n'
  else
    printf 'no snapshots, no servers running\n\n'
  fi
  usage_lines
}

# ── entry ────────────────────────────────────────────────────────────────────

tmux_snapshot_main() { # <status|save|restore|restore-server> [label]
  case $1 in
    status) cmd_status ;;
    save) cmd_save ;;
    restore) cmd_restore ;;
    restore-server)
      # The label as a positional, for running from outside the target server:
      # the save, kill, restore cycle cannot be driven from inside the server
      # it kills.
      [ "$#" -ge 2 ] || die 'restore-server requires a label (e.g. restore-server weaver)'
      [ "$ALL" = 1 ] && die '-a is not supported for restore-server (single server only)'
      LABEL=$2 LABEL_SET=1
      cmd_restore
      ;;
    *) return 2 ;;
  esac
}
