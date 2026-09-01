#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "--stash plans an update for a dirty worktree instead of skipping it"

# Without it a worktree with uncommitted changes is left alone, which is the
# safe default. --stash says put the changes aside, update, put them back, so
# the worktree has to reach the plan at all.

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
    "-C /wt/foo rev-list --merges --parents refs/remotes/origin/HEAD..HEAD") : ;;
    "rev-list --count refs/remotes/origin/HEAD..refs/heads/feature/foo") echo 0 ;;
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
stash=1
PLAN=''

plan_worktrees >/dev/null 2>&1

expected=planned
case "$PLAN" in
  *feature/foo*) actual=planned ;;
  *) actual=skipped ;;
esac
assert_eq "$actual" "$expected"
