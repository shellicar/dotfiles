#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "git refresh leaves the removal of a subagent branch created recently unticked"

# A finished subagent can be resumed while its session lives, and its worktree
# is its working folder. Two days old is too recent to tick.
#
#   main                A - B - C
#   worktree-agent-abc      B      (never diverged, worktree /wt/agent, 2 days old)
NOW=$(date +%s)

commit A
commit B A
commit C B

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/worktree-agent-abc B
branch_created refs/heads/worktree-agent-abc $((NOW - 2 * 86400))

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

expected='off|remove|never diverged from main'
actual=$(printf '%s' "$ROWS" | awk -F"$TAB" '$1 == "worktree-agent-abcR" { print $2 "|" $3 "|" $6; exit }')
assert_eq "${actual:-<no removal row>}" "$expected"
