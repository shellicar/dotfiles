# bash interactive config.
# The prompt reports pane state to tmux by printf alone (OSC 7 cwd, OSC 2 status
# glyph and project folder), so there is no tmux subprocess and it does not use
# the __tmux_* helpers.

# --- prompt ---
# Folder shown in the tmux window status: the nearest enclosing .git root, or the
# cwd itself when there is none. Walked with builtins alone, and recomputed only
# when the cwd changes, so the prompt stays free of subprocesses.
__tmux_folder() {
  [ "$PWD" = "$__tmux_folder_pwd" ] && return
  __tmux_folder_pwd=$PWD
  local d=$PWD
  while [ "$d" != / ] && [ ! -e "$d/.git" ]; do
    d=${d%/*}
    [ -z "$d" ] && d=/
  done
  [ "$d" = / ] && d=$PWD
  __tmux_folder_name=${d##*/}
  __tmux_folder_name=${__tmux_folder_name:-/}
}

__prompt_command() {
  local EXIT="$?"  # This needs to be first

  # tmux integration, printf-only (no tmux subprocess): OSC 7 reports the cwd
  # (populates pane_path); OSC 2 carries "<glyph> <folder>", the command state
  # (✅ ok / ❌ failed) alongside the project folder, which .tmux.conf splits back
  # into its two fields. The DEBUG trap re-sends the same pair with ⏳ while a
  # command runs. Raw $PWD keeps spaces intact.
  if [[ -n $TMUX ]]; then
    printf '\e]7;file://%s%s\e\\' "$HOSTNAME" "$PWD"
    __tmux_folder
    if [ $EXIT != 0 ]; then printf '\e]2;❌ %s\e\\' "$__tmux_folder_name"; else printf '\e]2;✅ %s\e\\' "$__tmux_folder_name"; fi
  fi

  local RCol='\[\e[0m\]'
  local Red='\[\e[0;31m\]'
  local Gre='\[\e[0;32m\]'
  local BYel='\[\e[1;33m\]'
  local BBlu='\[\e[1;34m\]'
  local Pur='\[\e[0;35m\]'
  local Dim='\[\e[0;90m\]'

  PS1="${Dim}\D{%d/%m %H:%M:%S}${RCol} "

  if [ $EXIT != 0 ]; then
    PS1+="${Red}\u${RCol}"  # Add red if exit code non 0
  else
    PS1+="${Gre}\u${RCol}"
  fi

  PS1+="${RCol}@${BBlu}\h ${Pur}\W${BYel}$ ${RCol}"
}
# DEBUG trap: mark the pane 'running' via OSC 2 (printf, no tmux subprocess).
_tmux_running() { [[ -n $TMUX ]] && printf '\e]2;⏳ %s\e\\' "$__tmux_folder_name"; }
PROMPT_COMMAND=__prompt_command
trap '_tmux_running' DEBUG
