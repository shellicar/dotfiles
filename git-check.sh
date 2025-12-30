#!/bin/sh

set -u

# Color definitions
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  RESET='\033[0m'
else
  GREEN=''
  YELLOW=''
  RED=''
  RESET=''
fi

# Emojis
CHECKMARK='✅'
CROSS='❌'

get_main_branch() {
  local branch
  branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "Error: Failed to get main branch from origin/HEAD" >&2
    exit 1
  fi
  echo "$branch" | sed 's@^refs/remotes/origin/@@'
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

ensure_in_git_repository() {
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository" >&2
    exit 1
  fi
}

fetch_latest_origin_data() {
  log "Fetching latest data from origin..."
  if ! git fetch origin > /dev/null 2>&1; then
    echo "Warning: Could not fetch from origin. Proceeding with local data." >&2
  fi
}

validate_main_branch_exists() {
  local main_branch="$1"
  log "Checking if origin/${main_branch} exists..."
  if ! branch_exists "origin/${main_branch}"; then
    echo "Error: origin/${main_branch} branch does not exist." >&2
    echo "Make sure you have fetched from origin and that the main branch exists." >&2
    exit 1
  fi
}

validate_arguments() {
  local check_all="$1"
  local target_branch="$2"
  
  if [ "$check_all" = "false" ] && [ -z "$target_branch" ]; then
    echo "Error: Please specify a branch name or use the --all flag." >&2
    echo "Usage: $0 [-d|--delete] [-a|--all] [branch_name]" >&2
    exit 1
  fi
}

check_all_local_branches() {
  local delete_branch="$1"
  local main_branch="$2"
  
  log "Checking all local branches..."
  for branch in $(git for-each-ref --format '%(refname:short)' refs/heads/); do
    if [ "$branch" != "${main_branch}" ]; then
      log "Checking branch: $branch"
      has_branch_been_merged "$branch" "$delete_branch" "$main_branch"
    fi
  done
}

check_specified_branch() {
  local target_branch="$1"
  local delete_branch="$2"
  local main_branch="$3"
  
  log "Checking specified branch: $target_branch"
  if ! branch_exists "$target_branch"; then
    echo "Error: Specified branch '$target_branch' does not exist." >&2
    echo "Available local branches:" >&2
    git branch >&2
    exit 1
  fi
  has_branch_been_merged "$target_branch" "$delete_branch" "$main_branch"
}

branch_exists() {
  if git rev-parse --verify "$1" > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

find_common_ancestor_with_main() {
  local branch="$1"
  local main_branch="$2"
  log "Finding base commit for branch: $branch"
  local common_ancestor
  common_ancestor=$(git merge-base "$branch" "origin/${main_branch}")
  log "Base commit: $common_ancestor"
  echo "$common_ancestor"
}

get_diff_content_only() {
  git diff "$1" "$2" | sed -n '/^---/!p' \
  | sed -n '/^+++/!p' \
  | sed -n '/^@@/!p'  \
  | sed -n '/^index /!p'
}

get_branch_tip_commit() {
  git rev-parse "$1"
}

get_branch_diff_content() {
  local base_commit="$1"
  local target_commit="$2"
  get_diff_content_only "$base_commit" "$target_commit"
}

handle_branch_already_merged() {
  local target_branch="$1"
  local delete_branch="$2"
  local commit="$3"
  
  echo "${GREEN}${CHECKMARK} Branch $target_branch has been merged${RESET} (found on commit: $commit)"
  if [ "$delete_branch" = "true" ]; then
    git branch -D "$target_branch"
  fi
}

search_for_matching_changes_in_main() {
  local target_branch="$1"
  local delete_branch="$2"
  local base_commit="$3"
  local target_changes="$4"
  local main_branch="$5"
  local prev_commit="$base_commit"

  for commit in $(git rev-list --reverse "$base_commit"..origin/${main_branch}); do
    local commit_changes
    commit_changes=$(get_diff_content_only "$prev_commit" "$commit")
    prev_commit=$commit

    if [ "$commit_changes" = "$target_changes" ]; then
      echo "${GREEN}${CHECKMARK} Branch $target_branch has been merged${RESET} (found on commit: $commit)"
      if [ "$delete_branch" = "true" ]; then
        git branch -D "$target_branch"
      fi
      return 0
    fi
  done
  return 1
}

has_branch_been_merged() {
  local target_branch=$1
  local delete_branch=$2
  local main_branch=$3

  local base_commit
  base_commit=$(find_common_ancestor_with_main "$target_branch" "$main_branch")

  local target_commit
  target_commit=$(get_branch_tip_commit "$target_branch")

  local target_changes
  target_changes=$(get_branch_diff_content "$base_commit" "$target_commit")

  if [ "$base_commit" = "$target_commit" ]; then
    handle_branch_already_merged "$target_branch" "$delete_branch" "$base_commit"
    return 0
  fi 

  if search_for_matching_changes_in_main "$target_branch" "$delete_branch" "$base_commit" "$target_changes" "$main_branch"; then
    return 0
  fi

  echo "${YELLOW}${CROSS} Branch $target_branch has not been merged into origin/${main_branch}${RESET}"
  return 1
}

parse_arguments() {
  local args_target_branch=""
  local args_delete_branch=false
  local args_check_all=false
  
  while [ $# -gt 0 ]; do
    case "$1" in
      -d|--delete)
        args_delete_branch=true
        shift
        ;;
      -a|--all)
        args_check_all=true
        shift
        ;;
      -h|--help)
        echo "Usage: $0 [-d|--delete] [-a|--all] [branch_name]"
        echo "  -d, --delete  Delete the branch if it has been merged"
        echo "  -a, --all     Check all branches"
        echo "  -h, --help    Show this help message"
        exit 0
        ;;
      -*)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
      *)
        if [ -n "$args_target_branch" ]; then
          echo "Error: Multiple branch names specified" >&2
          exit 1
        fi
        args_target_branch="$1"
        shift
        ;;
    esac
  done
  
  printf '"%s" %s %s' "$args_target_branch" "$args_delete_branch" "$args_check_all"
}

main() {
  local target_branch=""
  local delete_branch=false
  local check_all=false
  local main_branch
  
  main_branch=$(get_main_branch)
  log "Detected main branch: $main_branch"
  
  set -- $(parse_arguments "$@")
  target_branch=$(echo "$1" | tr -d '"')
  delete_branch="$2"
  check_all="$3"
  
  ensure_in_git_repository
  fetch_latest_origin_data
  validate_main_branch_exists "$main_branch"
  validate_arguments "$check_all" "$target_branch"

  if [ "$check_all" = "true" ]; then
    check_all_local_branches "$delete_branch" "$main_branch"
  else
    check_specified_branch "$target_branch" "$delete_branch" "$main_branch"
  fi
}

main "$@"
