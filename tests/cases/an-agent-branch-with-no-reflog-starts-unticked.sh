#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "git refresh leaves an empty subagent branch unticked when it has no reflog to date it"

# Without a reflog there is no creation date, and an unknown age is not an old
# one. The tip's date is no substitute: the tip is a commit of main.
#
#   main                A - B - C
#   worktree-agent-abc      B      (never diverged, worktree /wt/agent, no reflog)
NOW=$(date +%s)

commit A
commit B A
commit C B

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/worktree-agent-abc B

worktree_for refs/heads/main /repo
worktree_for refs/heads/worktree-agent-abc /wt/agent

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

NO_FETCH=true

analyse > "$WORK/analyse.out" 2>&1
derive

assert_asked 'reflog --date=unix --format=%gd refs/heads/worktree-agent-abc'

expected='off|remove|never diverged from main'
actual=$(printf '%s' "$ROWS" | awk -F"$TAB" '$1 == "worktree-agent-abcR" { print $2 "|" $3 "|" $6; exit }')
assert_eq "${actual:-<no removal row>}" "$expected"
