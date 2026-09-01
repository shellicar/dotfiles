#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a branch cut from another branch is left alone and names the branch"

# The pair to the case above, so the fix for one cannot quietly undo the other.
# Neither rebase is right here: a plain one copies the parent's commits onto
# this branch, a fork-point one drops them and leaves it built on nothing.

git_says() {
  case "$*" in
    "-C . rev-list --merges --parents refs/remotes/origin/HEAD..HEAD") return 0 ;;
    "rev-list --count refs/remotes/origin/HEAD..refs/heads/feature/top") echo 3 ;;
    "for-each-ref --format=%(refname) refs/heads refs/remotes")
      printf '%s\n' refs/heads/feature/base refs/heads/feature/top refs/heads/main ;;
    "rev-list refs/remotes/origin/HEAD..refs/heads/feature/top --not "*)
      printf '%s\n' top-commit-3 top-commit-2 top-commit-1 ;;
    "rev-list refs/remotes/origin/HEAD..refs/heads/feature/top")
      printf '%s\n' top-commit-3 top-commit-2 top-commit-1 ;;
    "rev-parse --verify --quiet top-commit-1^") echo tip-of-base ;;
    # Where it was cut is not on main: it was cut from another branch.
    "merge-base --is-ancestor tip-of-base refs/remotes/origin/HEAD") return 1 ;;
    "for-each-ref --contains tip-of-base --format=%(refname:short) refs/heads refs/remotes")
      printf '%s\n' feature/base feature/top ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected="none${TAB}cut from feature/base, not from main"
actual=$(update_verdict . feature/top)
assert_eq "$actual" "$expected"
