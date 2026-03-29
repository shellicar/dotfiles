# pnpm
export PNPM_HOME="/Users/stephen/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
export PATH="$HOME/.local/bin:$PATH"
export GPG_TTY=$(tty)

export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

bindkey -e
bindkey '^[[1~' beginning-of-line    # Home
bindkey '^[[3~' delete-char          # Del
bindkey '^[[4~' end-of-line          # End
bindkey '^[[5~' up-history           # Page Up (if you use it)
bindkey '^[[6~' down-history         # Page Down
bindkey '^[[1;5A' history-beginning-search-backward
bindkey '^[[1;5B' history-beginning-search-forward
# The following lines have been added by Docker Desktop to enable Docker CLI completions.
fpath=(/Users/stephen/.docker/completions $fpath)
autoload -Uz compinit
compinit
# End of Docker CLI completions
