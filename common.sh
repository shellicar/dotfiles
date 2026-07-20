#!/bin/sh
# Portable interactive config — aliases and functions for any shell, any OS.

# --- aliases ---
alias vi='vim'
alias gitlog='git log --graph --oneline'

# --- git ---
git_main() {
  # Fetch and prune branches
  echo "Fetching"
  if git fetch -p; then
    # Check if 'main' branch exists on remote
    if git ls-remote --heads origin main | grep 'refs/heads/main' >/dev/null; then
      target_branch="main"
    elif git ls-remote --heads origin master | grep 'refs/heads/master' >/dev/null; then
      # Fallback to 'master' if 'main' does not exist
      target_branch="master"
    else
      echo "Neither 'main' nor 'master' branch exists on remote."
      return 1
    fi
    echo "Target branch: $target_branch"

    # Get the current branch name
    current_branch=$(git branch --show-current)
    echo "Current branch: $current_branch"

    # Check if the current branch is 'main'
    if [ "$current_branch" = "$target_branch" ]; then
      # Pull the latest changes on 'main'
      echo "Pulling"
      git pull
    else
      # Check if 'main' branch exists locally
      if git rev-parse --verify $target_branch >/dev/null 2>&1; then
        # Delete 'main' branch if it exists
        echo "Deleting target branch"
        git branch -d $target_branch
      fi
      # Checkout 'main' branch
      echo "Checking out target branch"
      git checkout $target_branch --
    fi
  else
    echo "Failed to fetch branches."
  fi
}

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
  if [[ -n "$1" ]]; then
    session_match="$(tmux ls -F '#{session_name}' | grep -i "$1" | head -n 1)"
  else
    session_match="$(tmux ls -F '#{session_name}' | head -n 1)"
  fi

  if [[ -n "$session_match" ]]; then
    if [[ -n "$TMUX" ]]; then
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
        @="$(docker ps -qa)";
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
