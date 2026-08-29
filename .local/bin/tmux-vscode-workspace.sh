#!/bin/sh
# Retarget this tmux server's dedicated VS Code workspace to the focused pane's repo.
#
# Identity = the per-server .code-workspace file (one per tmux server).
# Content  = the folders listed inside it, added to as panes are focused and dropped
#            when the directory goes.
#
# Rewriting the file live-updates the already-open window in place.
# The window is opened (osascript) only when none exists yet. `code` CLI does not
# work from a run-shell hook, so osascript is used to open.
exec >> /tmp/tmux-vscode-workspace.log 2>&1

JQ=/usr/bin/jq
REALPATH=/bin/realpath
HS=/opt/homebrew/bin/hs
OSASCRIPT=/usr/bin/osascript

SERVER=$(basename "$(tmux display-message -p '#{socket_path}')")
SESSION=$(tmux display-message -p '#{session_name}')
PANE_PATH=$(tmux display-message -p '#{pane_current_path}')

# Walk up to the git root. If the pane is not inside a git repo, abort below —
# leave the window on whatever it is showing rather than retarget to a non-repo dir.
DIR="$PANE_PATH"
while [ "$DIR" != "/" ]; do
  [ -e "$DIR/.git" ] && break
  DIR=$(dirname "$DIR")
done
[ "$DIR" = "/" ] && exit 0   # not in a repo: abort, change nothing
REPO=$(basename "$DIR")

# Display name shown in the title — maps a server name to a nicer label,
# falling back to the server (socket) name: workspaceName[server] ?? server.
case "$SERVER" in
  shellicar) NAME="@shellicar" ;;
  *)         NAME="$SERVER" ;;
esac

TITLE="$NAME - $SESSION - $REPO"

# Per-server palette (active / inactive). Title bar only — chrome stays default.
case "$SERVER" in
  weaver)             ACTIVE="#0ea5e9"; INACTIVE="#075985" ;;  # sky
  shellicar)          ACTIVE="#06b6d4"; INACTIVE="#155e75" ;;  # cyan
  hellicar-solutions) ACTIVE="#2563eb"; INACTIVE="#1e3a8a" ;;  # blue
  hope-ventures)      ACTIVE="#16a34a"; INACTIVE="#14532d" ;;
  *)                  ACTIVE="#6a737d"; INACTIVE="#3a3f44" ;;
esac

WS_DIR="$HOME/.vscode-tmux"
mkdir -p "$WS_DIR"
WS_FILE="$WS_DIR/$SERVER.code-workspace"

# The folder list grows as panes are focused, and an entry is dropped only once its
# directory has gone. That removal restarts the extension host, which prompts for
# confirmation when an extension editor such as a preview is open. An unparseable
# file has already lost its folder list, so rebuild from this repo.
#
# Only an entry whose path is a string with no newline is kept, because the resolve
# below carries one line per entry through a pipe: a newline inside a path would add
# a line and pair every later entry with another entry's answer.
EXISTING='[]'
if [ -f "$WS_FILE" ]; then
  EXISTING=$("$JQ" -c '[ (if (.folders | type) == "array" then .folders else [] end)[] | select((.path | type) == "string" and (.path | contains("\n") | not)) ]' "$WS_FILE" 2>/dev/null) || EXISTING='[]'
  [ -z "$EXISTING" ] && EXISTING='[]'
fi

# A relative path is resolved against this file's own directory, which is what it is
# relative to: VS Code writes one that way when a folder is added through its UI, and
# the dedupe below matches on the path string. An absolute path already is that answer,
# and stripping a leading slash is what tells the two apart. A folder that has gone
# resolves to nothing and leaves an empty slot, which keeps this list index-aligned
# with $EXISTING so the two pair up.
RESOLVED=$(printf '%s' "$EXISTING" | "$JQ" -r '.[].path' | while IFS= read -r ENTRY; do
  ABS="$ENTRY"
  [ "${ENTRY#/}" = "$ENTRY" ] && ABS=$(cd "$WS_DIR" && "$REALPATH" "$ENTRY" 2>/dev/null)
  [ -d "$ABS" ] || ABS=
  printf '%s\n' "$ABS"
done | "$JQ" -R -s -c 'split("\n") | .[:-1]')

NEW=$("$JQ" -n \
  --argjson existing "$EXISTING" \
  --argjson resolved "$RESOLVED" \
  --arg folder "$DIR" \
  --arg title "$TITLE" \
  --arg active "$ACTIVE" \
  --arg inactive "$INACTIVE" \
  '{
     folders: (
       ([ $existing, $resolved ] | transpose | map(select(.[1] != "") | .[0] + { path: .[1] }))
       + [ { path: $folder } ]
       | reduce .[] as $f ([]; if any(.[]; .path == $f.path) then . else . + [$f] end)
       | sort_by(.name // (.path | split("/") | last))
     ),
     settings: {
       "window.title": $title,
       "workbench.colorCustomizations": {
         "titleBar.activeBackground": $active,
         "titleBar.activeForeground": "#ffffff",
         "titleBar.inactiveBackground": $inactive,
         "titleBar.inactiveForeground": "#ffffffb3"
       }
     }
   }')

# Retarget: rewrite the workspace file only when something actually changed.
# Written through a rename so a reader never sees a half-written file. VS Code
# behaves the same whether the file is replaced or truncated in place.
#
# A failed merge leaves nothing to write, and writing that would replace the folder
# list with an empty file, so the last good one stands instead.
if [ -n "$NEW" ] && { [ ! -f "$WS_FILE" ] || [ "$NEW" != "$(cat "$WS_FILE")" ]; }; then
  printf '%s\n' "$NEW" > "$WS_FILE.tmp"
  mv "$WS_FILE.tmp" "$WS_FILE"
fi

# Does this server already have a window? Match the title prefix we set.
OPEN=$("$HS" -c 'local a=hs.application.get("Code"); local p="'"$NAME"' - "; local found="n"; if a then for _,w in ipairs(a:allWindows()) do local t=w:title() or ""; if t:sub(1,#p)==p then found="y"; break end end end; print(found)' 2>/dev/null)

# No window yet: open one (osascript brings VS Code forward on first open).
if [ "$OPEN" != "y" ]; then
  "$OSASCRIPT" -e 'tell application "Visual Studio Code" to open POSIX file "'"$WS_FILE"'"' >/dev/null 2>&1
fi
