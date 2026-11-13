#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "git refresh ticks the removal of an empty subagent branch"

# Claude Code names a subagent's branch worktree-agent-*. When one is empty and
# its worktree is unlocked, clean and holds no ignored files, its removal starts
# ticked, and the row says why. The update is masked by the ticked removal.
#
# Run through analyse as well as derive, so the facts are gathered the way the
# command gathers them.
#
#   main                A - B - C
#   worktree-agent-abc      B      (never diverged, worktree /wt/agent)

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

row() {
  printf '%s' "$ROWS" | awk -F"$TAB" -v op="$1" '$1 == op { print $2 "|" $4 "|" $6; exit }'
}

expected='on|remove worktree-agent-abc and its worktree|never diverged from main, agent branch'
actual=$(row worktree-agent-abcR)
assert_eq "${actual:-<no removal row>}" "$expected"

expected='skip|fast-forward worktree-agent-abc|skipped, the removal above takes it'
actual=$(row worktree-agent-abcU)
assert_eq "${actual:-<no update row>}" "$expected"
