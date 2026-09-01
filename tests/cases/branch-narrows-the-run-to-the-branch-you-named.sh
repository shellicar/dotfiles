#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "--branch narrows the run to the branch you named"

# Naming a branch has to keep every other branch out of the work, not just out
# of the report. The index built for the content walk is sized from the branches
# under consideration, so if a branch you did not name still influences it, the
# narrowing is not real.

git_says() {
  case "$*" in
    "for-each-ref --format %(refname:short) refs/heads/")
      printf '%s\n' near far ;;
    "merge-base refs/heads/near refs/remotes/origin/HEAD") echo near-base ;;
    "merge-base refs/heads/far refs/remotes/origin/HEAD") echo far-base ;;
    "merge-base --is-ancestor refs/heads/near refs/remotes/origin/HEAD") return 1 ;;
    "merge-base --is-ancestor refs/heads/far refs/remotes/origin/HEAD") return 1 ;;
    "rev-list --count near-base..refs/remotes/origin/HEAD") echo 5 ;;
    "rev-list --count far-base..refs/remotes/origin/HEAD") echo 50 ;;
    "rev-parse --verify --quiet refs/heads/near"|"rev-parse --verify --quiet refs/heads/far") return 1 ;;
    "rev-list --count refs/remotes/origin/HEAD ^refs/heads/near") echo 5 ;;
    "rev-list --count refs/remotes/origin/HEAD ^refs/heads/far") echo 50 ;;
    "log -1 --format=%ct refs/heads/near"|"log -1 --format=%ct refs/heads/far") echo 999999999 ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

NOW=1000000000
whole=$(compute_max_walk_depth)
ONLY_BRANCHES='near'
narrowed=$(compute_max_walk_depth)

expected="whole=50 narrowed=5"
actual="whole=$whole narrowed=$narrowed"
assert_eq "$actual" "$expected"
