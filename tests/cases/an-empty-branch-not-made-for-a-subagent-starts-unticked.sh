#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "git refresh leaves an empty branch unticked unless a subagent made it"

# Only worktree-agent-* branches start ticked. Any other empty branch is held
# back the way git cleanup holds it behind --empty.

git_says() { fail "deriving asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash, other authors, merged pull
# request, commits the rebase replays, merge edits the rebase drops
BFACTS="feature/idle${TAB}/wt/idle${TAB}empty${TAB}0${TAB}0${TAB}never diverged from main${TAB}0${TAB}-${TAB}-${TAB}-${TAB}-${TAB}[0 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-${TAB}no${TAB}-${TAB}-$NL"
DFACTS=''

derive

expected='off|never diverged from main'
actual=$(printf '%s' "$ROWS" | awk -F"$TAB" '$1 == "feature/idleR" { print $2 "|" $6; exit }')
assert_eq "${actual:-<no removal row>}" "$expected"
