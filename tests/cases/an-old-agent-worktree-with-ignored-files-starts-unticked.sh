#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "git refresh leaves an old subagent worktree unticked when it holds ignored files"

# git worktree remove deletes ignored files without a word, so a worktree
# holding any is never removed by default, however old its branch is.

git_says() { fail "deriving asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

NOW=$(date +%s)
created=$((NOW - 30 * 86400))

# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash, other authors, merged pull
# request, commits the rebase replays, merge edits the rebase drops, created
BFACTS="worktree-agent-abc${TAB}/wt/agent${TAB}empty${TAB}0${TAB}0${TAB}never diverged from main${TAB}0${TAB}-${TAB}-${TAB}-${TAB}1 ignored entries: .env${TAB}[0 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-${TAB}no${TAB}-${TAB}-${TAB}$created$NL"
DFACTS=''

derive

expected='off|never diverged from main'
actual=$(printf '%s' "$ROWS" | awk -F"$TAB" '$1 == "worktree-agent-abcR" { print $2 "|" $6; exit }')
assert_eq "${actual:-<no removal row>}" "$expected"
