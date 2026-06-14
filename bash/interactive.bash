# bash interactive config.
# Relies on the prompt status helpers (__tmux_*) defined in common.sh,
# which load.sh sources before this file.

# --- prompt ---
__prompt_command() {
  local EXIT="$?"  # This needs to be first
  local timestamp
  timestamp=$(date '+%d/%m %H:%M:%S')

  local RCol='\[\e[0m\]'
  local Red='\[\e[0;31m\]'
  local Gre='\[\e[0;32m\]'
  local BYel='\[\e[1;33m\]'
  local BBlu='\[\e[1;34m\]'
  local Pur='\[\e[0;35m\]'
  local Dim='\[\e[0;90m\]'

  PS1="${Dim}${timestamp}${RCol} "

  if [ $EXIT != 0 ]; then
    PS1+="${Red}\u${RCol}"  # Add red if exit code non 0
    __tmux_failure
  else
    PS1+="${Gre}\u${RCol}"
    __tmux_success
  fi

  PS1+="${RCol}@${BBlu}\h ${Pur}\W${BYel}$ ${RCol}"
}
PROMPT_COMMAND=__prompt_command
trap '__tmux_question' DEBUG
