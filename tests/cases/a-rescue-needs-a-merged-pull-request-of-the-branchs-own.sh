#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "git refresh rescues only when the branch's own pull request merged, and rebases otherwise"

# Both branches have commits on top of a commit whose work is in main. For
# feature/pr that commit is the last one of a merged pull request, so what sits
# above it was added after the merge, and it is offered the rescue. feature/plain
# has no merged pull request in its history, so its landed commit reached main
# some other way: it is offered a rebase from there, ticked, and keeps its
# branch and worktree.
#
#   main           A - S - T           S squashes K, T squashes L
#   feature/pr      \ K - P1           K is the last commit of merged PR #3
#   feature/plain   \ L - Q1
commit A
commit S A
commit T S
commit K A
commit P1 K
commit L A
commit Q1 L
lands K
lands L

ref_set refs/heads/main T
ref_set refs/remotes/origin/HEAD T
ref_set refs/heads/feature/pr P1
ref_set refs/heads/feature/plain Q1
worktree_for refs/heads/main /repo
worktree_for refs/heads/feature/pr /wt/pr
worktree_for refs/heads/feature/plain /wt/plain

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

# The pull request query, answered here: the source branch, its last commit,
# and the squash it made on main. The branch name differs from feature/pr on
# purpose, since the last commit is what is matched.
fetch_pr_merges() {
  PR_MERGE_TABLE="fix/k${TAB}K${TAB}S"
  PR_SOURCE='from the case'; PR_HINT=''
}

NO_FETCH=true
NOW=$(date +%s)
WALK_DEPTH=50

analyse > "$WORK/analyse.out" 2>&1
derive

row() { printf '%s' "$ROWS" | awk -F"$TAB" -v id="$1" '$1 == id { print $2 "|" $3 "|" $6; exit }'; }

assert_eq "$(row feature/prR)" "off|rescue|merged, 1 commit on top not in main"
assert_eq "$(row feature/prU)" ""
assert_eq "$(row feature/plainR)" ""
assert_eq "$(row feature/plainU)" "on|rebase|2 behind, replays 1"
