eval "$(/opt/homebrew/bin/brew shellenv)"

if [[ "$OSTYPE" == "darwin"* ]]; then
    bindkey "^R" history-incremental-search-backward
fi

autoload -Uz compinit && compinit

. "$HOME/.profile"
