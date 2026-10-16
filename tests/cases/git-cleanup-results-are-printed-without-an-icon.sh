#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "git cleanup: carrying out its plan prints each result line with no action icon"

# git cleanup shares run_plan with git refresh. git refresh hands each action
# the icon its plan showed; git cleanup's plan hands none, and its result
# lines stay as they were: a status mark and the branch, nothing between.

git_says() {
  case "$*" in
    "-C /wt/parked status --porcelain --ignored") return 0 ;;
    "show-ref --verify --quiet refs/heads/rescue/feature/x") return 1 ;;
    "branch -D feature/done"|"branch -D feature/x") return 0 ;;
    "branch -D feature/held") echo 'error: branch is held' >&2; return 1 ;;
    "worktree remove /wt/parked") return 0 ;;
    "rev-parse --verify --quiet refs/heads/rescue/feature/x") return 1 ;;
    "worktree add -q --detach "*|"worktree remove "*) return 0 ;;
    "switch -q -c rescue/feature/x refs/heads/feature/x") return 0 ;;
    "rebase -q --onto refs/remotes/origin/HEAD B") return 0 ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-cleanup
. "$REPO/home/common/bin/git-cleanup"

# run_rescue's scratch worktree is a real mktemp directory.
TMPDIR=$WORK
export TMPDIR

APPLY=true
APPLY_DETACHED=true
RESCUE=true
MERGED_COUNT=0
DETACHED_COUNT=0

PLAN=''
do_delete feature/done '' '✅' merged '[0 ahead]' true --apply MERGED_COUNT >/dev/null
do_delete feature/held '' '✅' merged '[0 ahead]' true --apply MERGED_COUNT >/dev/null
do_delete_worktree /wt/parked wt-parked 'parked on main' '[parked]' >/dev/null
do_rescue feature/x B 2 '' >/dev/null

actual=$(run_plan 2>&1)

expected="  ✅ feature/done removed
  ⚠️ feature/held: branch delete failed, skipped
     ↳ error: branch is held
  ✅ wt-parked removed
  feature/x
     ↳ rescued 2 → rescue/feature/x (onto main); original removed"
assert_eq "$actual" "$expected"
