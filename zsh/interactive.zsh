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

# no-op widget: consume a key silently (used for Insert)
_noop() { }
zle -N _noop

# Home / End (plain + shift/alt/ctrl)
for k in '^[[H' '^[OH' '^[[1~' '^[[1;2H' '^[[1;3H' '^[[1;5H'; do bindkey "$k" beginning-of-line; done
for k in '^[[F' '^[OF' '^[[4~' '^[[1;2F' '^[[1;3F' '^[[1;5F'; do bindkey "$k" end-of-line; done

# Left / Right: move a char; ctrl/alt move a word
for k in '^[[D' '^[OD' '^[[1;2D'; do bindkey "$k" backward-char; done
for k in '^[[C' '^[OC' '^[[1;2C'; do bindkey "$k" forward-char; done
for k in '^[[1;3D' '^[[1;5D'; do bindkey "$k" backward-word; done
for k in '^[[1;3C' '^[[1;5C'; do bindkey "$k" forward-word; done

# Up / Down: recall history; ctrl searches history
for k in '^[[A' '^[OA' '^[[1;2A' '^[[1;3A'; do bindkey "$k" up-line-or-history; done
for k in '^[[B' '^[OB' '^[[1;2B' '^[[1;3B'; do bindkey "$k" down-line-or-history; done
bindkey '^[[1;5A' history-beginning-search-backward
bindkey '^[[1;5B' history-beginning-search-forward

# Delete: a char; ctrl/alt delete a word
for k in '^[[3~' '^[[3;2~'; do bindkey "$k" delete-char; done
for k in '^[[3;3~' '^[[3;5~'; do bindkey "$k" kill-word; done

# Page Up / Page Down (plain + mods): history
for k in '^[[5~' '^[[5;2~' '^[[5;3~' '^[[5;5~'; do bindkey "$k" up-line-or-history; done
for k in '^[[6~' '^[[6;2~' '^[[6;3~' '^[[6;5~'; do bindkey "$k" down-line-or-history; done

# Insert (plain + mods): swallowed, since there is no overwrite indicator
for k in '^[[2~' '^[[2;2~' '^[[2;3~' '^[[2;5~'; do bindkey "$k" _noop; done

# Backspace / Return / Space with modifiers (csi-u)
bindkey '^[[127;2u' backward-delete-char  # shift+backspace
bindkey '^[[127;5u' backward-kill-word    # ctrl+backspace
bindkey '^[[13;2u'  accept-line           # shift+return
bindkey '^[[13;5u'  accept-line           # ctrl+return
bindkey -s '^[[32;2u' ' '                 # shift+space

bindkey '^R' history-incremental-search-backward

# --- completion ---
fpath=($HOME/.docker/completions $fpath)
autoload -Uz compinit
if [[ -n $HOME/.zcompdump(#qN.mh+24) ]]; then
  compinit          # dump older than 24h → full rebuild + security audit
else
  compinit -C       # recent dump → load it and skip the audit
fi
