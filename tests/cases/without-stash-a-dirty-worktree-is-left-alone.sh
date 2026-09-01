#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "without --stash a dirty worktree is left out of the plan"

# The pair to stash-updates-a-dirty-worktree-instead-of-skipping-it. Uncommitted
# work is never moved unless you asked for it to be.

git_says() {
  case "$*" in
    "worktree list --porcelain")
      printf 'worktree /wt/foo\nHEAD foo-tip\nbranch refs/heads/feature/foo\n' ;;
    "-C /wt/foo status --porcelain") echo " M some-file" ;;
    "-C /wt/foo symbolic-ref --quiet --short HEAD") echo feature/foo ;;
    "-C /wt/foo rev-list --count HEAD..main-tip") echo 2 ;;
    "-C /wt/foo rev-list --count main-tip..HEAD") echo 0 ;;
    "-C /wt/foo rev-parse --verify --quiet @{u}") echo upstream-tip ;;
    "-C /wt/foo merge-base --is-ancestor upstream-tip HEAD") return 0 ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-spread
. "$REPO/home/common/bin/git-spread"

MAIN=main
MAIN_REF=refs/remotes/origin/HEAD
target=main-tip
apply=1
stash=0
PLAN=''

plan_worktrees >/dev/null 2>&1

expected=skipped
case "$PLAN" in
  *feature/foo*) actual=planned ;;
  *) actual=skipped ;;
esac
assert_eq "$actual" "$expected"
