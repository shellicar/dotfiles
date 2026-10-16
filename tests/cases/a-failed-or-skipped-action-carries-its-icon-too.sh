#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "git refresh: a failed or skipped action's warning carries the icon its action had in the plan"

# The ⚠️ says it did not go through; the icon beside it says which action did
# not. Each worktree below is set up to fail in one way, so every warning the
# run can print about a branch's action appears once.
#
# The decisions (where a rebase starts, which commit landed) are stubbed below,
# because this case is about what is printed once they are made.

git_says() {
  case "$*" in
    "branch -D fix/gone") echo 'error: branch is held' >&2; return 1 ;;
    "worktree remove /wt/parked") echo 'fatal: worktree is locked' >&2; return 1 ;;
    "-C /wt/pushed rev-parse --verify --quiet @{u}"|"-C /wt/rebase-push rev-parse --verify --quiet @{u}")
      echo upstream-tip ;;
    "-C "*" rev-parse --verify --quiet @{u}") return 1 ;;
    "-C "*" rev-parse --short HEAD") echo abc1234 ;;
    "-C /wt/stash stash push --quiet --include-untracked") return 1 ;;
    "-C /wt/pop stash push --quiet --include-untracked") return 0 ;;
    "-C /wt/pop stash pop --quiet") return 1 ;;
    "-C /wt/pop "*" merge --ff-only "*) return 0 ;;
    "-C /wt/ff "*" merge --ff-only "*) return 1 ;;
    "-C /wt/merge "*" merge "*) echo 'error: conflict in a-file' >&2; return 1 ;;
    "-C /wt/merge merge --abort") return 0 ;;
    "-C /wt/pushed "*" merge "*) return 0 ;;
    "-C /wt/pushed push --quiet") return 1 ;;
    "-C /wt/rebase rebase --quiet --onto "*) echo 'error: could not apply a-commit' >&2; return 1 ;;
    "-C /wt/rebase rebase --abort") return 0 ;;
    "-C /wt/rebase-push rebase --quiet --onto "*) return 0 ;;
    "-C /wt/rebase-push push --quiet --force-with-lease") return 1 ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# fix/nolanded has no landed commit, so its rescue never reaches the plan.
landed_commit() {
  case "$1" in
    refs/heads/fix/nolanded) echo none ;;
    *) printf 'found\tB\n' ;;
  esac
}
rebase_from() {
  case "$1" in
    fix/skip) printf 'none\tits work is already in %s\n' "$MAIN" ;;
    *) printf 'rebase\tB\n' ;;
  esac
}

ROWS=''
emit fix/goneR on remove 'remove fix/gone' '' 'merged' - - merged '[0 ahead]'
emit wt-parkedD on detach 'remove wt-parked' /wt/parked 'parked' - - detached '[parked]'
emit fix/nolandedR on rescue 'rescue 1 off fix/nolanded' '' 'merged, 1 on top' - 1 review '[2 ahead]'
emit fix/ffU on ff 'fast-forward fix/ff' /wt/ff 'behind' - - unmerged '[0 ahead]'
emit fix/mergeU on merge 'merge into fix/merge' /wt/merge 'behind' - - unmerged '[1 ahead]'
emit fix/pushedU on merge 'merge into fix/pushed' /wt/pushed 'behind' - - unmerged '[1 ahead]'
emit fix/skipU on rebase 'rebase fix/skip' /wt/skip 'behind' - - unmerged '[1 ahead]'
emit fix/rebaseU on rebase 'rebase fix/rebase' /wt/rebase 'behind' - - unmerged '[1 ahead]'
emit fix/rebase-pushU on rebase 'rebase fix/rebase-push' /wt/rebase-push 'behind' - - unmerged '[1 ahead]'
emit fix/stashU on rebase 'rebase fix/stash' /wt/stash 'behind' - - unmerged '[1 ahead]' yes
emit fix/popU on ff 'fast-forward fix/pop' /wt/pop 'behind' - - unmerged '[0 ahead]' yes

PLAN=''
actual=$( { build_plan; run_plan; } 2>&1)

# The long dash the library writes between a failure and git's reason.
D=$(printf '\342\200\224')

expected="  ⚠️ 🛟 fix/nolanded: no landed commit found, rescue skipped
  ⚠️ 🔥 fix/gone: branch delete failed, skipped
     ↳ error: branch is held
  ⚠️ 🔥 wt-parked: worktree remove failed, skipped
     ↳ fatal: worktree is locked
  ⚠️ ⏩ fix/ff: cannot fast-forward (local commits?), skipped
  ⚠️ 🔀 fix/merge: merge failed, aborted and untouched $D conflict in a-file
  ⚠️ 🔀 fix/pushed: merged, but the push failed. The merge is local only: push it, or undo it with git switch -C fix/pushed abc1234
  ⚠️ 🔁 fix/skip: its work is already in main, skipped
  ⚠️ 🔁 fix/rebase: rebase failed, aborted and untouched $D could not apply a-commit
  ⚠️ 🔁 fix/rebase-push: rebased, but the push was refused (the remote moved) $D push it yourself
  ⚠️ 🔁 fix/stash: could not set the working tree aside, skipped
  ✅ ⏩ fix/pop fast-forwarded
  ⚠️ ⏩ fix/pop: could not put the working tree back, it is in the stash list"
assert_eq "$actual" "$expected"
