#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "git refresh ticks the removal of an empty subagent branch created a week or more ago"

# Claude Code names a subagent's branch worktree-agent-*. Once one has sat
# empty for AGENT_IDLE_DAYS it starts ticked, and the row says why. The age is
# when the branch was created, from its reflog, not its tip's date: the tip is a
# commit of main.
#
# Run through analyse as well as derive, so the creation date is read the way
# the command reads it.
#
#   main                A - B - C
#   worktree-agent-abc      B      (never diverged, worktree /wt/agent, 8 days old)
NOW=$(date +%s)

commit A
commit B A
commit C B

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/worktree-agent-abc B
branch_created refs/heads/worktree-agent-abc $((NOW - 8 * 86400))

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

row() {
  printf '%s' "$ROWS" | awk -F"$TAB" -v op="$1" '$1 == op { print $2 "|" $3 "|" $6; exit }'
}

expected='on|remove|never diverged from main, agent worktree created 7+ days ago'
actual=$(row worktree-agent-abcR)
assert_eq "${actual:-<no removal row>}" "$expected"

expected='skip|ff|skipped, the removal above takes it'
actual=$(row worktree-agent-abcU)
assert_eq "${actual:-<no update row>}" "$expected"
