#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a removal that can run shows its ignored entries in the picker and the plan, ticked or not"

# The entries are what the removal would delete, and for a subagent branch they
# are also why its removal starts unticked, so they are shown whether the row is
# ticked or not. A removal that cannot run deletes nothing, so its [-] row does
# not show them.

git_says() { fail "deriving, drawing and printing ask git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

stty() { [ "$1" = size ] && { echo '24 200'; return 0; }; return 1; }

# worktree-agent-abc: empty, ignored .env, so its removal starts unticked.
# merged/one: merged, ignored node_modules/, so its removal starts ticked.
# empty/dirty: empty, dirty, ignored dist/, so its removal is unavailable.
#
# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash, other authors, merged pull
# request, commits the rebase replays, merge edits the rebase drops
BFACTS="worktree-agent-abc${TAB}/wt/agent${TAB}empty${TAB}0${TAB}0${TAB}never diverged from main${TAB}0${TAB}-${TAB}-${TAB}-${TAB}1 ignored entries: .env${TAB}[0 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-${TAB}no${TAB}-${TAB}-$NL"
BFACTS="${BFACTS}merged/one${TAB}/wt/one${TAB}merged${TAB}3${TAB}0${TAB}merged${TAB}0${TAB}-${TAB}-${TAB}-${TAB}1 ignored entries: node_modules/${TAB}[3 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-${TAB}no${TAB}-${TAB}-$NL"
BFACTS="${BFACTS}empty/dirty${TAB}/wt/dirty${TAB}empty${TAB}0${TAB}0${TAB}never diverged from main${TAB}0${TAB}worktree has uncommitted changes${TAB}-${TAB}-${TAB}1 ignored entries: dist/${TAB}[0 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-${TAB}no${TAB}-${TAB}-$NL"
DFACTS=''

derive

state=$(printf '%s' "$ROWS" | awk -F"$TAB" '$1 == "worktree-agent-abcR" { print $2; exit }')
assert_eq "$state" off

# line_of <text> <screen>: the line of the screen that names the text.
line_of() { printf '%s\n' "$2" | grep -F -- "$1" | head -1; }

screen=$(draw)
assert_contains "$(line_of 'remove worktree-agent-abc' "$screen")" 'also deletes 1 ignored entries: .env'
assert_contains "$(line_of 'remove merged/one' "$screen")" 'also deletes 1 ignored entries: node_modules/'
assert_not_contains "$screen" 'dist/'

plan=$(say_selected 'Plan' all)
# The entries are on the line under the row.
after=$(printf '%s\n' "$plan" | awk '/remove worktree-agent-abc/ { getline; print; exit }')
assert_contains "$after" 'also deletes 1 ignored entries: .env'
after=$(printf '%s\n' "$plan" | awk '/remove merged\/one/ { getline; print; exit }')
assert_contains "$after" 'also deletes 1 ignored entries: node_modules/'
assert_not_contains "$plan" 'dist/'
