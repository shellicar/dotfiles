#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "git refresh ticks the removal of an empty subagent branch with no reflog when git logs ref updates"

# With core.logAllRefUpdates=true git writes a reflog for every branch, so a
# branch without one has outlived it: git gc expired the entries. That makes it
# older than AGENT_IDLE_DAYS, and its removal starts ticked.
#
#   main                A - B - C
#   worktree-agent-abc      B      (never diverged, worktree /wt/agent, no reflog)
NOW=$(date +%s)
FAKE_LOG_REF_UPDATES=true

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

assert_asked 'reflog --no-show-signature --date=unix --format=%gd refs/heads/worktree-agent-abc'

expected='on|remove|never diverged from main, agent branch with an expired reflog'
actual=$(printf '%s' "$ROWS" | awk -F"$TAB" '$1 == "worktree-agent-abcR" { print $2 "|" $3 "|" $6; exit }')
assert_eq "${actual:-<no removal row>}" "$expected"
