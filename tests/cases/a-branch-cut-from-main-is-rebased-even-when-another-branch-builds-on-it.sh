#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a branch cut from main is rebased even when another branch builds on it"

# feature/base was cut from main and feature/top was cut from base, so every
# commit on base is also on top. That says nothing about base: it was cut from
# main and a rebase onto main is exactly right for it. Refusing leaves the
# bottom of every stack behind.

git_says() {
  case "$*" in
    # No merge of main into it, so a rebase is the strategy.
    "-C . rev-list --merges --parents refs/remotes/origin/HEAD..HEAD") return 0 ;;
    # Two commits of its own.
    "rev-list --count refs/remotes/origin/HEAD..refs/heads/feature/base") echo 2 ;;
    # Both of them are also on feature/top.
    "for-each-ref --format=%(refname) refs/heads refs/remotes")
      printf '%s\n' refs/heads/feature/base refs/heads/feature/top refs/heads/main ;;
    "rev-list refs/remotes/origin/HEAD..refs/heads/feature/base --not "*) : ;;
    "rev-list refs/remotes/origin/HEAD..refs/heads/feature/base")
      printf '%s\n' base-commit-2 base-commit-1 ;;
    "rev-parse --verify --quiet base-commit-1^") echo cut-from-here ;;
    # Where it was cut is on main, so it was cut from main.
    "merge-base --is-ancestor cut-from-here refs/remotes/origin/HEAD") return 0 ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

expected="rebase${TAB}cut-from-here"
actual=$(update_verdict . feature/base)
assert_eq "$actual" "$expected"
