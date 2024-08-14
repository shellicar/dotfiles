#!/bin/bash

MAIN_BRANCH=main

# Function to check if a branch exists
branch_exists() {
    git rev-parse --verify $1 > /dev/null 2>&1
}

# Function to find the closest common ancestor commit of the given branch and origin/main
find_base_commit() {
    git merge-base $1 origin/${MAIN_BRANCH}
}

# Function to get the changes introduced between two commits
get_commit_changes() {
    git diff $1 $2 | sed -n '/^---/!p' \
  | sed -n '/^+++/!p' \
  | sed -n '/^@@/!p'  \
  | sed -n '/^index /!p'
}

# Function to check if a single branch has been merged into origin/main
check_single_branch() {
    local target_branch=$1
    local delete_branch=$2

    # Find the base commit
    local base_commit=$(find_base_commit $target_branch)

    # Get the tip commit of the target branch
    local target_commit=$(git rev-parse $target_branch)

    # Get the changes from the common ancestor to the tip of the branch
    local target_changes=$(get_commit_changes $base_commit $target_commit)

    # Initialize a variable to keep track of the previous commit hash
    local prev_commit=$base_commit

    if [[ "$base_commit" == "$target_commit" ]]; then
      echo "Found contents for $target_branch on commit: $base_commit"
      # echo "Details:"
      # git log -1 $commit
      if [ "$delete_branch" = true ]; then
          git branch -D $target_branch
          # echo "Deleted branch: $target_branch"
      fi
      return 0
    fi 

    # Iterate over each commit in origin/main since the base commit
    for commit in $(git rev-list --reverse $base_commit..origin/${MAIN_BRANCH}); do
        # Get the changes introduced in this commit against its immediate parent
        local commit_changes=$(get_commit_changes $prev_commit $commit)

        # Update the previous commit hash for the next iteration
        prev_commit=$commit

        # Compare the changes
        if [[ "$commit_changes" == "$target_changes" ]]; then
            echo "Found contents for $target_branch on commit: $commit"
            # echo "Details:"
            # git log -1 $commit
            if [ "$delete_branch" = true ]; then
                git branch -D $target_branch
                # echo "Deleted branch: $target_branch"
            fi
            return 0
        fi
    done

    echo "Branch $target_branch has not been merged into origin/${MAIN_BRANCH}"
    return 1
}

# Initialize variables
target_branch=""
delete_branch=false
check_all=false

# Parse options
OPTS=$(getopt -o "da" -l "delete,all" -- "$@")
if [ $? != 0 ]; then
    echo "Failed to parse options"
    exit 1
fi

eval set -- "$OPTS"

while true; do
    case "$1" in
        -d|--delete)
            delete_branch=true
            shift
            ;;
        -a|--all)
            check_all=true
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Programming error"
            exit 1
            ;;
    esac
done

# Check if the branches exist
if ! branch_exists "origin/${MAIN_BRANCH}"; then
    echo "origin/${MAIN_BRANCH} branch does not exist."
    exit 1
fi

# The remaining argument should be the branch name or we should check all branches
if [ "$check_all" = false ] && [ "$#" -eq 0 ]; then
    echo "Please specify a branch name or use the --all flag."
    exit 1
fi

if [ "$check_all" = true ]; then
    for branch in $(git for-each-ref --format '%(refname:short)' refs/heads/); do
        if [ "$branch" != "${MAIN_BRANCH}" ]; then
            check_single_branch $branch $delete_branch
        fi
    done
else
    target_branch=$1
    if ! branch_exists "$target_branch"; then
        echo "Specified branch does not exist."
        exit 1
    fi
    check_single_branch $target_branch $delete_branch
fi
