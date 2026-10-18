#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "git refresh leaves an empty subagent branch unticked when its reflog cannot be read or does not parse"

# In a repository that logs ref updates, a reflog that reads as empty means it
# expired, and the branch counts as old. A read that fails, or prints something
# that is not name@{seconds}, says nothing about the age, so the branch stays
# unticked: one created today may still have a subagent to resume. The failed
# read prints a date 30 days old, so only its exit status can leave it unticked.
#
#   main                    A - B - C
#   worktree-agent-garbled      B      (reflog prints a line that does not parse)
#   worktree-agent-failed       B      (reflog fails, after printing an old date)
NOW=$(date +%s)
FAKE_LOG_REF_UPDATES=true

commit A
commit B A
commit C B

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/worktree-agent-garbled B
ref_set refs/heads/worktree-agent-failed B
reflog_says refs/heads/worktree-agent-garbled 0 'worktree-agent-garbled@{yesterday}'
reflog_says refs/heads/worktree-agent-failed 128 "worktree-agent-failed@{$((NOW - 30 * 86400))}"

worktree_for refs/heads/main /repo
worktree_for refs/heads/worktree-agent-garbled /wt/garbled
worktree_for refs/heads/worktree-agent-failed /wt/failed

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

expected='off|remove|never diverged from main'
actual=$(row worktree-agent-garbledR)
assert_eq "${actual:-<no removal row>}" "$expected"
actual=$(row worktree-agent-failedR)
assert_eq "${actual:-<no removal row>}" "$expected"
