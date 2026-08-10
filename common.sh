#!/bin/sh
# Portable interactive config — aliases and functions for any shell, any OS.

# --- aliases ---
alias vi='vim'
alias gitlog='git log --graph --oneline'

# --- git ---
# wt <branch> [base] — create a sibling worktree (<repo>--<leaf>) via the "git
# wt-create" alias (fetch, worktree add, pnpm install if applicable), then cd into
# it. A git alias can't cd the caller (runs in a subprocess), so the cd lives here.
wt() {
  [ -n "$1" ] || { echo "usage: wt <branch> [base]" >&2; return 1; }
  dest=$(git wt-create "$@") || return
  cd "$dest" || return
}

# --- tmux ---
tm() {
    if [ $# -eq 0 ]; then
        if tmux list-s; then
            tmux a
        else
            tmux
        fi
    else
        tmux "$@"
    fi
}

tmuxa() {
  if [ -n "$1" ]; then
    session_match="$(tmux ls -F '#{session_name}' | grep -i "$1" | head -n 1)"
  else
    session_match="$(tmux ls -F '#{session_name}' | head -n 1)"
  fi

  if [ -n "$session_match" ]; then
    if [ -n "$TMUX" ]; then
      tmux switch-client -t "$session_match"
    else
      tmux a -t "$session_match"
    fi
  else
    echo "No matching session found."
    return 1
  fi
}

# --- docker ---
docker_ip() {
    if [ "$#" = "0" ]; then
        # shellcheck disable=SC2046 # container ids are hex with no spaces; splitting into separate arguments is the point
        set -- $(docker ps -qa)
    fi

    docker inspect --format '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$@"
}
alias docker-ip='docker_ip'

docker_enter() {
    if [ "$#" = 0 ]; then
        echo "usage: docker-enter <container-name>"
    elif [ "$#" = 1 ]; then
        docker exec -it "$1" /bin/bash -l
    else
        docker exec -it "$@"
    fi
}

docker_login() {
    if [ "$#" = 1 ]; then
        docker exec -it "$1" login -f "$(whoami)"
    elif [ "$#" = 2 ]; then
        docker exec -it "$1" login -f "$2"
    else
        echo "usage: docker-login <container-name> [user]"
    fi
}

alias docker-enter="docker_enter"
alias docker-login="docker_login"
