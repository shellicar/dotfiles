#!/bin/sh
# window-status.sh — render a tmux window-status entry.
#
# The renderer reads no tmux state directly; user-option values come in as
# args from the format string. This keeps invocation cheap (no tmux IPC per
# render) since the format runs every status-interval per window.
#
# Window-scope inputs (identify the window/project):
#   @title  — replaces the cwd-folder slot (left field)
#   @colour — fg colour for the title slot
#             (name kept for cutover; semantically @title-colour)
#   @state  — appended in brackets when set; shared status board
#
# Pane-scope inputs (per the active pane of the window):
#   @role   — replaces the derived process-name slot (right field)
#   @status — glyph prefixed to the entry (e.g. ✅/❌/⏳); written by the prompt
#
# Usage:
#   window-status.sh [--current] <window_idx> <pane_idx> <pane_pid> \
#                    <pane_current_path> <@title> <@colour> <@state> \
#                    <@role> <@status>
#
# Output shape:
#   [<status> ]<title>.<W>.<P>:<role>[ [state]]
# where <title> defaults to the cwd .git-root basename (pane-path.sh) and
# <role> defaults to the derived process name (pane-name.sh). Each slot can
# be independently overridden via the inputs above.

current=0
if [ "$1" = "--current" ]; then
  current=1
  shift
fi

window_idx="$1"
pane_idx="$2"
pane_pid="$3"
pane_path="$4"
title="$5"
colour="$6"
state="$7"
role="$8"
status="$9"

script_dir="$(dirname "$0")"

# Title colour is constant: @colour or the fallback — it never varies with
# focus (a tagged title doesn't, so the fallback mustn't either; the underline
# marks the active window). Only the machinery text (index/process) brightens
# on the active window.
title_default_fg=colour81
if [ "$current" = "1" ]; then
  index_fg=colour250
  process_fg=colour255
else
  index_fg=colour244
  process_fg=colour250
fi
role_fg=colour209
state_fg=colour141

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
