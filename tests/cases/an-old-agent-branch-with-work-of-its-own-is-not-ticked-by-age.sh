#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "git refresh does not tick an old subagent branch that has commits not in main"

# Age ticks only an empty branch. A subagent branch with a commit on top of
# what main has is a rescue, and that starts unticked whatever its age.

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
BFACTS="worktree-agent-abc${TAB}/wt/agent${TAB}review${TAB}2${TAB}1${TAB}merged, 1 commit on top not in main${TAB}0${TAB}-${TAB}-${TAB}-${TAB}-${TAB}[2 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-${TAB}yes${TAB}-${TAB}-${TAB}$created$NL"
DFACTS=''

derive

expected='off|rescue|merged, 1 commit on top not in main'
actual=$(printf '%s' "$ROWS" | awk -F"$TAB" '$1 == "worktree-agent-abcR" { print $2 "|" $3 "|" $6; exit }')
assert_eq "${actual:-<no removal row>}" "$expected"
