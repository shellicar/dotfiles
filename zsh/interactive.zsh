# zsh interactive config.
# Relies on the prompt status helpers (__tmux_*) defined in common.sh,
# which load.sh sources before this file.

# --- prompt ---
__prompt_command() {
  local EXIT="$?"  # This needs to be first

  local RCol="%f"
  local Red="%F{red}"
  local Gre="%F{green}"
  local BYel="%F{yellow}"
  local BBlu="%F{39}"
  local Pur="%F{magenta}"
  local Dim="%F{8}"

  local user_part="%n"
  local host_part="%m"
  local dir_part="%1~"

  if [ $EXIT != 0 ]; then
    __tmux_failure
    PROMPT="${Dim}%D{%d/%m %H:%M:%S}${RCol} ${Red}${user_part}${RCol}@${BBlu}${host_part} ${Pur}${dir_part}${BYel}$ ${RCol}"
  else
    __tmux_success
    PROMPT="${Dim}%D{%d/%m %H:%M:%S}${RCol} ${Gre}${user_part}${RCol}@${BBlu}${host_part} ${Pur}${dir_part}${BYel}$ ${RCol}"
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd __prompt_command
add-zsh-hook preexec __tmux_question

# --- keybindings ---
bindkey -e
bindkey '^[[1~' beginning-of-line    # Home
bindkey '^[[3~' delete-char          # Del
bindkey '^[[4~' end-of-line          # End
bindkey '^[[5~' up-history           # Page Up (if you use it)
bindkey '^[[6~' down-history         # Page Down
bindkey '^[[1;5A' history-beginning-search-backward
bindkey '^[[1;5B' history-beginning-search-forward
bindkey "^R" history-incremental-search-backward

# --- completion ---
fpath=($HOME/.docker/completions $fpath)
autoload -Uz compinit
compinit
