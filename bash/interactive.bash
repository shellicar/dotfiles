# bash interactive config.
# The prompt reports pane state to tmux by printf alone (OSC 7 cwd, OSC 2 status
# glyph) — no tmux subprocess, so it does not use the __tmux_* helpers.

# --- prompt ---
__prompt_command() {
  local EXIT="$?"  # This needs to be first

  # tmux integration, printf-only (no tmux subprocess): OSC 7 reports the cwd
  # (populates pane_path); OSC 2 reports command state as a glyph in the pane
  # title (✅ ok / ❌ failed), read by window-status.sh. The DEBUG trap emits ⏳
  # while a command runs. Raw $PWD keeps spaces intact.
  if [[ -n $TMUX ]]; then
    printf '\e]7;file://%s%s\e\\' "$HOSTNAME" "$PWD"
    if [ $EXIT != 0 ]; then printf '\e]2;❌\e\\'; else printf '\e]2;✅\e\\'; fi
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
_tmux_running() { [[ -n $TMUX ]] && printf '\e]2;⏳\e\\'; }
PROMPT_COMMAND=__prompt_command
trap '_tmux_running' DEBUG
