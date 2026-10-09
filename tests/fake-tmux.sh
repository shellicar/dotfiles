# Sourced by the tmux-snapshot cases, after harness.sh.
#
# A live server described as tables, and the listings tmux would print for
# it. The listing renders whatever -F format it is asked for, the way tmux does,
# so a case cannot pass by answering the one format the library happens to use:
# asked for '#{session_name}' alone on a server with a session called "", it
# prints an empty line, as tmux does.
#
#   FAKE_SESSIONS  one session per line: id <US> name
#   FAKE_WINDOWS   one window per line:  session id <US> window index
#   FAKE_PANES     one pane per line:    session id <US> window index <US> window
#                  name <US> layout <US> pane index <US> cwd <US> command <US> pid
#                  (its user options are empty)
#
# No sessions means no server, and the listings fail as tmux's do.

FUS=$(printf '\037')
FRS=$(printf '\036')
FAKE_SESSIONS=''
FAKE_WINDOWS=''
FAKE_PANES=''

# Substitutes each #{name} in a format with its value.
fake_render() { # <format> [<name> <value>]...
  local out var val
  out=$1
  shift
  while [ $# -ge 2 ]; do
    var=$1 val=$2
    shift 2
    while :; do
      case $out in *"#{$var}"*) ;; *) break ;; esac
      out="${out%%"#{$var}"*}$val${out#*"#{$var}"}"
    done
  done
  printf '%s\n' "$out"
}

fake_session_name() { # <id>
  local id name
  while IFS=$FUS read -r id name; do
    [ "$id" = "$1" ] && { printf '%s' "$name"; return 0; }
  done <<EOF
$FAKE_SESSIONS
EOF
  return 1
}

# The answer to list-sessions, list-windows -a or list-panes -a, or 2 when the
# call is something else, so the case can answer it.
#
# US in the output is printed the way tmux 3.7 prints it: as is with -u, as '_'
# without (no UTF-8 locale here). FAKE_TMUX_35=1 prints it as '\037', as tmux
# 3.5 does even with -u. RS is treated the same way (as '\036' for 3.5), which
# was seen only for US; with -u, tmux 3.7c prints RS as is (tests/tmux).
FAKE_TMUX_35=0
fake_listing() { # tmux's arguments
  local out status utf8
  utf8=0
  [ "$1" = -u ] && { utf8=1; shift; }
  out=$(fake_listing_raw "$@")
  status=$?
  [ "$status" -eq 0 ] || return "$status"
  if [ "$FAKE_TMUX_35" = 1 ]; then
    printf '%s\n' "$out" | sed "s/$FUS/\\\\037/g; s/$FRS/\\\\036/g"
  elif [ "$utf8" = 1 ]; then
    printf '%s\n' "$out"
  else
    printf '%s\n' "$out" | sed "s/$FUS/_/g; s/$FRS/_/g"
  fi
}

fake_listing_raw() {
  local fmt id name idx wname layout pidx path cmd pid
  [ "$1" = -L ] && shift 2
  case $1 in list-sessions | list-windows | list-panes) ;; *) return 2 ;; esac
  if [ -z "$FAKE_SESSIONS" ]; then
    echo "no server running on /tmp/tmux-1000/fake" >&2
    return 1
  fi
  case "$*" in
    "list-sessions -F "*)
      fmt=${*#list-sessions -F }
      while IFS=$FUS read -r id name; do
        [ -n "$id" ] || continue
        fake_render "$fmt" session_id "$id" session_name "$name"
      done <<EOF
$FAKE_SESSIONS
EOF
      ;;
    "list-windows -a -F "*)
      fmt=${*#list-windows -a -F }
      while IFS=$FUS read -r id idx; do
        [ -n "$id" ] || continue
        fake_render "$fmt" session_id "$id" session_name "$(fake_session_name "$id")" window_index "$idx"
      done <<EOF
$FAKE_WINDOWS
EOF
      ;;
    "list-panes -a -F "*)
      fmt=${*#list-panes -a -F }
      while IFS=$FUS read -r id idx wname layout pidx path cmd pid; do
        [ -n "$id" ] || continue
        fake_render "$fmt" session_name "$(fake_session_name "$id")" window_index "$idx" \
          window_name "$wname" window_layout "$layout" pane_index "$pidx" \
          pane_current_path "$path" pane_current_command "$cmd" pane_pid "$pid" \
          @title '' @colour '' @state '' @role '' @status ''
      done <<EOF
$FAKE_PANES
EOF
      ;;
    *) return 2 ;;
  esac
}

# Server options, kept in a file because the fake answers in a subshell. Answers
# set-option -s <name> <value> and set-option -su <name>, or returns 2. A global
# session option (-g) is a different table in tmux, and is not answered.
FAKE_OPTIONS=$WORK/tmux-options
: > "$FAKE_OPTIONS"

fake_option() { # tmux's arguments
  [ "$1" = -u ] && shift
  [ "$1" = -L ] && shift 2
  case "$1 $2" in
    'set-option -s') [ $# -eq 4 ] || return 2 ;;
    'set-option -su') [ $# -eq 3 ] || return 2 ;;
    *) return 2 ;;
  esac
  [ -n "$FAKE_SESSIONS" ] || { echo "no server running on /tmp/tmux-1000/fake" >&2; return 1; }
  grep -v "^$3$FUS" "$FAKE_OPTIONS" > "$FAKE_OPTIONS.new"
  [ "$2" = -s ] && printf '%s\n' "$3$FUS$4" >> "$FAKE_OPTIONS.new"
  mv "$FAKE_OPTIONS.new" "$FAKE_OPTIONS"
}

# The value of a server option, or nothing when it is unset.
fake_option_value() { # <name>
  grep "^$1$FUS" "$FAKE_OPTIONS" | cut -d "$FUS" -f 2-
}

fake_option_is_set() { # <name>
  grep -q "^$1$FUS" "$FAKE_OPTIONS"
}

# Fields separated by US, one line: what a plan step or a status row is.
snap_line() {
  local IFS
  IFS=$FUS
  printf '%s\n' "$*"
}

# A pane record in the snapshot format, ended by RS and a newline: session,
# window index, window name, layout, pane index, cwd, command, launcher,
# @title, @colour, @state, @role, @status.
snap_record() {
  local IFS
  IFS=$FUS
  printf '%s%s\n' "$*" "$FRS"
}

# A pane record with the fields a case does not care about filled in.
snap_pane() { # <session> <window index> <window name> <pane index> [cwd] [launcher]
  snap_record "$1" "$2" "$3" "layout-$2" "$4" "${5:-/}" sh "${6:-}" '' '' '' '' ''
}

# A snapshot file in the format: the version line, the saved line, the panes.
snap_file() { # <file> <pane records>
  printf 'tmux-snapshot 2\nsaved 2026-10-09 12:00\n%s\n' "$2" > "$1"
}

# Snapshots go under the case's own directory, never the real one.
XDG_DATA_HOME=$WORK/data
export XDG_DATA_HOME

# What the command line would have set.
LABEL=fake LABEL_SET=1 ALL=0 APPLY=0 TS_LABEL=fake
