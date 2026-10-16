#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "git refresh: each result line carries the icon its action had in the plan"

# The plan shows 🔥 🛟 ⏩ 🔀 🔁 for what each row will do. Once it runs, the
# line saying how it went has to name the same action, or you cannot tell from
# the output what was done to which branch.
#
# Every operation succeeds here. The decisions (where a rebase starts, which
# commit landed) are stubbed below, because this case is about what is printed
# once they are made, not about making them.

git_says() {
  case "$*" in
    "branch -D "*|"worktree add -q --detach "*|"worktree remove "*) return 0 ;;
    "rev-parse --verify --quiet refs/heads/rescue/fix/rescue") return 1 ;;
    "switch -q -c rescue/fix/rescue refs/heads/fix/rescue") return 0 ;;
    "rebase -q --onto refs/remotes/origin/HEAD B") return 0 ;;
    "-C /wt/merge rev-parse --verify --quiet @{u}") echo upstream-tip ;;
    "-C "*" rev-parse --verify --quiet @{u}") return 1 ;;
    "-C "*" rev-parse --short HEAD") echo abc1234 ;;
    "-C "*" merge "*) return 0 ;;
    "-C /wt/merge push --quiet") return 0 ;;
    "-C /wt/rebase rebase --quiet --onto refs/remotes/origin/HEAD B") return 0 ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

landed_commit() { printf 'found\tB\n'; }
rebase_from() { printf 'rebase\tB\n'; }

# run_rescue's scratch worktree is a real mktemp directory.
TMPDIR=$WORK
export TMPDIR

ROWS=''
emit fix/goneR on remove 'remove fix/gone' '' 'merged' - - merged '[0 ahead]'
emit wt-parkedD on detach 'remove wt-parked' /wt/parked 'parked on a landed commit' - - detached '[parked]'
emit fix/rescueR on rescue 'rescue 2 off fix/rescue, then remove it' '' \
  'merged, 2 commits on top not in main' - 2 review '[4 ahead]'
emit fix/ffU on ff 'fast-forward fix/ff' /wt/ff 'behind' - - unmerged '[0 ahead]'
emit fix/mergeU on merge 'merge into fix/merge' /wt/merge 'behind' - - unmerged '[1 ahead]'
emit fix/localU on merge 'merge into fix/local' /wt/local 'behind' - - unmerged '[1 ahead]'
emit fix/rebaseU on rebase 'rebase fix/rebase' /wt/rebase 'behind' - - unmerged '[1 ahead]'

PLAN=''
build_plan
actual=$(run_plan 2>&1)

expected="  ✅ 🔥 fix/gone removed
  ✅ 🔥 wt-parked removed
  🛟 fix/rescue
     ↳ rescued 2 → rescue/fix/rescue (onto main); original removed
  ✅ ⏩ fix/ff fast-forwarded
  ✅ 🔀 fix/merge merged origin/main
  ✅ 🔀 fix/local merged origin/main locally, nothing to push it to (before: abc1234)
  ✅ 🔁 fix/rebase rebased onto origin/main"
assert_eq "$actual" "$expected"
