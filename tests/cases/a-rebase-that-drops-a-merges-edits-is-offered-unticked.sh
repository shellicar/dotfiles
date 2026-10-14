#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a rebase that drops a merge's own edits is offered unticked, naming the merge and its files"

# A rebase replays the commits that are not merges, so a merge's own edits go
# with it. That is a warning, not a refusal: the rebase is still on the list,
# unticked, with the merge and the files named. A rebase with nothing to drop
# keeps the ticked default. Which merges carry edits is git's answer
# (merge_edits); this is only what the list does with it.

git_says() { fail "deriving asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash, other authors, merged pull
# request, commits the rebase replays, merge edits the rebase drops
BFACTS="feature/merged${TAB}/wt/merged${TAB}review${TAB}6${TAB}3${TAB}3 commits on top of work already in main${TAB}4${TAB}-${TAB}rebase${TAB}L${TAB}-${TAB}[6 ahead, 1 day ago]${TAB}0${TAB}no${TAB}-${TAB}no${TAB}2${TAB}81d2743 edited probe/test.lua$NL"
BFACTS="${BFACTS}feature/clean${TAB}/wt/clean${TAB}review${TAB}5${TAB}1${TAB}1 commit on top of work already in main${TAB}4${TAB}-${TAB}rebase${TAB}L${TAB}-${TAB}[5 ahead, 1 day ago]${TAB}0${TAB}no${TAB}-${TAB}no${TAB}1${TAB}-$NL"
DFACTS=''

derive

row() { printf '%s' "$ROWS" | awk -F"$TAB" -v id="$1" '$1 == id { print $2 "|" $3 "|" $6; exit }'; }
assert_eq "$(row feature/mergedU)" "off|rebase|4 behind, replays 2, drops merge 81d2743 edited probe/test.lua"
assert_eq "$(row feature/cleanU)" "on|rebase|4 behind, replays 1"
assert_eq "$(row feature/mergedR)" ""
