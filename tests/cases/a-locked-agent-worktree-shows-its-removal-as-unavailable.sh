#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "git refresh shows a locked subagent worktree's removal as unavailable"

# An empty subagent branch's removal starts ticked, but a lock still blocks it:
# git refuses to remove a locked worktree. The row is [-] and names the lock.
#
# Run through analyse as well as derive: the lock is found while the facts are
# gathered.
#
#   main                A - B - C
#   worktree-agent-abc      B      (never diverged, worktree /wt/agent, locked)

commit A
commit B A
commit C B

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/worktree-agent-abc B

worktree_for refs/heads/main /repo
worktree_for refs/heads/worktree-agent-abc /wt/agent
lock_worktree /wt/agent 'claude agent agent-abc (pid 4242)'

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

expected='skip|remove|never diverged from main, locked: claude agent agent-abc (pid 4242)'
actual=$(row worktree-agent-abcR)
assert_eq "${actual:-<no removal row>}" "$expected"

# The update is offered, and starts where the empty class starts it, off.
expected='off|ff|1 behind'
actual=$(row worktree-agent-abcU)
assert_eq "${actual:-<no update row>}" "$expected"
