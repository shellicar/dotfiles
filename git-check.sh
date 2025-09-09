#!/bin/sh

set -eu

MAIN_BRANCH=main

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
  log "Checking if origin/${MAIN_BRANCH} exists..."
  if ! branch_exists "origin/${MAIN_BRANCH}"; then
    echo "Error: origin/${MAIN_BRANCH} branch does not exist." >&2
    echo "Make sure you have fetched from origin and that the main branch exists." >&2
    exit 1
  fi
}

validate_arguments() {
  if [ "$check_all" = "false" ] && [ -z "$target_branch" ]; then
    echo "Error: Please specify a branch name or use the --all flag." >&2
    echo "Usage: $0 [-d|--delete] [-a|--all] [branch_name]" >&2
    exit 1
  fi
}

check_all_local_branches() {
  log "Checking all local branches..."
  for branch in $(git for-each-ref --format '%(refname:short)' refs/heads/); do
    if [ "$branch" != "${MAIN_BRANCH}" ]; then
      log "Checking branch: $branch"
      has_branch_been_merged "$branch" "$delete_branch"
    fi
  done
}

check_specified_branch() {
  log "Checking specified branch: $target_branch"
  if ! branch_exists "$target_branch"; then
    echo "Error: Specified branch '$target_branch' does not exist." >&2
    echo "Available local branches:" >&2
    git branch >&2
    exit 1
  fi
  has_branch_been_merged "$target_branch" "$delete_branch"
}

branch_exists() {
  if git rev-parse --verify "$1" > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

find_common_ancestor_with_main() {
  log "Finding base commit for branch: $1"
  local common_ancestor
  common_ancestor=$(git merge-base "$1" "origin/${MAIN_BRANCH}")
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
  
  echo "Found contents for $target_branch on commit: $commit"
  if [ "$delete_branch" = "true" ]; then
    git branch -D "$target_branch"
  fi
}

search_for_matching_changes_in_main() {
  local target_branch="$1"
  local delete_branch="$2"
  local base_commit="$3"
  local target_changes="$4"
  local prev_commit="$base_commit"

  for commit in $(git rev-list --reverse "$base_commit"..origin/${MAIN_BRANCH}); do
    local commit_changes
    commit_changes=$(get_diff_content_only "$prev_commit" "$commit")
    prev_commit=$commit

    if [ "$commit_changes" = "$target_changes" ]; then
      echo "Found contents for $target_branch on commit: $commit"
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

  local base_commit
  base_commit=$(find_common_ancestor_with_main "$target_branch")

  local target_commit
  target_commit=$(get_branch_tip_commit "$target_branch")

  local target_changes
  target_changes=$(get_branch_diff_content "$base_commit" "$target_commit")

  if [ "$base_commit" = "$target_commit" ]; then
    handle_branch_already_merged "$target_branch" "$delete_branch" "$base_commit"
    return 0
  fi 

  if search_for_matching_changes_in_main "$target_branch" "$delete_branch" "$base_commit" "$target_changes"; then
    return 0
  fi

  echo "Branch $target_branch has not been merged into origin/${MAIN_BRANCH}"
  return 1
}

initialize_variables() {
  target_branch=""
  delete_branch=false
  check_all=false
}

parse_arguments() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -d|--delete)
        delete_branch=true
        shift
        ;;
      -a|--all)
        check_all=true
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
        if [ -n "$target_branch" ]; then
          echo "Error: Multiple branch names specified" >&2
          exit 1
        fi
        target_branch="$1"
        shift
        ;;
    esac
  done
}

main() {
  initialize_variables
  parse_arguments "$@"
  ensure_in_git_repository
  fetch_latest_origin_data
  validate_main_branch_exists
  validate_arguments

  if [ "$check_all" = "true" ]; then
    check_all_local_branches
  else
    check_specified_branch
  fi
}

main "$@"
