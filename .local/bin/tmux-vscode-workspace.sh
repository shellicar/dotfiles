#!/bin/sh
# Retarget this tmux server's dedicated VS Code workspace to the focused pane's repo.
#
# Identity = the per-server .code-workspace file (one per tmux server).
# Content  = the folder listed inside it.
#
# Rewriting the file live-updates the already-open window in place. On every focus
# the server's window is raised to the front so it is the visible VS Code window.
# The window is opened (osascript) only when none exists yet. `code` CLI does not
# work from a run-shell hook, so osascript is used to open.
exec >> /tmp/tmux-vscode-workspace.log 2>&1

JQ=/usr/bin/jq
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

NEW=$("$JQ" -n \
  --arg folder "$DIR" \
  --arg title "$TITLE" \
  --arg active "$ACTIVE" \
  --arg inactive "$INACTIVE" \
  '{
     folders: [ { path: $folder } ],
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
if [ ! -f "$WS_FILE" ] || [ "$NEW" != "$(cat "$WS_FILE")" ]; then
  printf '%s\n' "$NEW" > "$WS_FILE.tmp"
  mv "$WS_FILE.tmp" "$WS_FILE"
fi

# Find this server's window (match the title prefix we set) and raise it to the
# front so it is the visible VS Code window. raise() brings it forward WITHOUT
# taking keyboard focus from tmux; swap raise() -> focus() if you want the
# keyboard to follow into VS Code. Nothing here touches Spaces.
OPEN=$("$HS" -c 'local a=hs.application.get("Code"); local p="'"$NAME"' - "; local found="n"; if a then for _,w in ipairs(a:allWindows()) do local t=w:title() or ""; if t:sub(1,#p)==p then w:raise(); found="y"; break end end end; print(found)' 2>/dev/null)

# No window yet: open one (osascript brings VS Code forward on first open).
if [ "$OPEN" != "y" ]; then
  "$OSASCRIPT" -e 'tell application "Visual Studio Code" to open POSIX file "'"$WS_FILE"'"' >/dev/null 2>&1
fi
