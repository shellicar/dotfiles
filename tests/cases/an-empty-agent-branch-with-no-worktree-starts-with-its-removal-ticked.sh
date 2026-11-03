#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "git refresh ticks the removal of an empty subagent branch that has no worktree"

# With no worktree there is nothing to be locked, dirty or hold ignored files,
# so the removal of the branch alone starts ticked.

git_says() { fail "deriving asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash, other authors, merged pull
# request, commits the rebase replays, merge edits the rebase drops
BFACTS="worktree-agent-abc${TAB}-${TAB}empty${TAB}0${TAB}0${TAB}never diverged from main${TAB}0${TAB}-${TAB}-${TAB}-${TAB}-${TAB}[0 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-${TAB}no${TAB}-${TAB}-$NL"
DFACTS=''

derive

expected='on|remove worktree-agent-abc|-|never diverged from main, agent branch'
actual=$(printf '%s' "$ROWS" | awk -F"$TAB" '$1 == "worktree-agent-abcR" { print $2 "|" $4 "|" $5 "|" $6; exit }')
assert_eq "${actual:-<no removal row>}" "$expected"
