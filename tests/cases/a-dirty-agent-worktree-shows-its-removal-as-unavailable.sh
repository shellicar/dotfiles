#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "git refresh shows a dirty subagent worktree's removal as unavailable"

# An empty subagent branch's removal starts ticked, but uncommitted changes
# still block it, as they block every removal. The row is [-] and says so, and
# the update starts where the empty class starts it, off.

git_says() { fail "deriving asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash, other authors, merged pull
# request, commits the rebase replays, merge edits the rebase drops
BFACTS="worktree-agent-abc${TAB}/wt/agent${TAB}empty${TAB}0${TAB}0${TAB}never diverged from main${TAB}1${TAB}worktree has uncommitted changes${TAB}ff${TAB}-${TAB}-${TAB}[0 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-${TAB}no${TAB}-${TAB}-$NL"
DFACTS=''

row() {
  printf '%s' "$ROWS" | awk -F"$TAB" -v op="$1" '$1 == op { print $2 "|" $3 "|" $6; exit }'
}

derive

expected='skip|remove|never diverged from main, worktree has uncommitted changes'
actual=$(row worktree-agent-abcR)
assert_eq "${actual:-<no removal row>}" "$expected"

expected='off|ff|1 behind'
actual=$(row worktree-agent-abcU)
assert_eq "${actual:-<no update row>}" "$expected"
