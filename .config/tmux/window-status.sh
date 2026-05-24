#!/bin/sh
# window-status.sh — render a tmux window-status entry.
#
# Reads user options to override parts of the default rendering. Each option
# lives at its natural scope; the script queries explicitly so resolution
# doesn't depend on tmux's inheritance.
#
# Window-scope (identify the window/project):
#   @title  — replaces the cwd-folder slot (left field)
#   @colour — fg colour for the title slot
#             (name kept for cutover; semantically @title-colour)
#   @state  — appended in brackets when set; shared status board
#
# Pane-scope (per the active pane of the window):
#   @role   — replaces the derived process-name slot (right field)
#   @status — glyph prefixed to the entry (e.g. ✅/❌/⏳); written by the prompt
#
# Usage:
#   window-status.sh [--current] <window_id> <pane_id> <pane_pid> <pane_current_path> <window_idx> <pane_idx>
#
# Output shape:
#   [<status> ]<title>.<W>.<P>:<role>[ [state]]
# where <title> defaults to the cwd .git-root basename and <role> defaults to
# the derived process name. Each slot can be independently overridden via the
# user options above.

current=0
if [ "$1" = "--current" ]; then
  current=1
  shift
fi

window_id="$1"
pane_id="$2"
pane_pid="$3"
pane_path="$4"
window_idx="$5"
pane_idx="$6"

script_dir="$(dirname "$0")"

# Palette differs between current and other windows so the active one stands out.
if [ "$current" = "1" ]; then
  title_default_fg=colour81
  index_fg=colour250
  process_fg=colour255
else
  title_default_fg=colour138
  index_fg=colour237
  process_fg=colour250
fi
role_fg=colour209
state_fg=colour141

# Window-scope options.
title=$(tmux show-options -wqv -t "$window_id" @title)
colour=$(tmux show-options -wqv -t "$window_id" @colour)
state=$(tmux show-options -wqv -t "$window_id" @state)

# Pane-scope options (active pane of the window).
role=$(tmux show-options -pqv -t "$pane_id" @role)
status=$(tmux show-options -pqv -t "$pane_id" @status)

# Title slot: @title overrides cwd; @colour overrides default fg.
if [ -n "$title" ]; then
  title_text="$title"
else
  title_text=$("$script_dir/pane-path.sh" "$pane_path")
fi
title_fg="${colour:-$title_default_fg}"

# Role slot: @role overrides derived process name and brings its own colour.
if [ -n "$role" ]; then
  right_text="$role"
  right_fg="$role_fg"
else
  right_text=$("$script_dir/pane-name.sh" "$pane_pid")
  right_fg="$process_fg"
fi

out=""
if [ -n "$status" ]; then
  out="$status "
fi
out="$out#[fg=$title_fg]$title_text#[fg=$index_fg].$window_idx.$pane_idx:#[fg=$right_fg]$right_text"
if [ -n "$state" ]; then
  out="$out #[fg=$state_fg][$state]"
fi

printf '%s' "$out"
