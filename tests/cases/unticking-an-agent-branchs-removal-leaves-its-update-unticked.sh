#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "unticking an old subagent branch's removal does not tick its fast-forward"

# While the removal is ticked the update is a [-] row, and it is first offered
# only once the removal is unticked. Its default comes from the class, which
# holds an empty branch's update off, not from the removal's own default. Were
# it the removal's, unticking the removal would tick the update, and the branch
# the command offered to delete would be maintained instead.

git_says() { fail "deriving asks git nothing: git $*"; }

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-refresh
. "$REPO/home/common/bin/git-refresh"

NOW=$(date +%s)
created=$((NOW - 30 * 86400))

# name, worktree, class, ahead, not in main, why, behind, block, update action,
# its detail, ignored, meta, unpushed, stash, other authors, created
BFACTS="worktree-agent-abc${TAB}/wt/agent${TAB}empty${TAB}0${TAB}0${TAB}never diverged from main${TAB}1${TAB}-${TAB}ff${TAB}-${TAB}-${TAB}[0 ahead, 5 days ago]${TAB}0${TAB}no${TAB}-${TAB}$created$NL"
DFACTS=''

state() {
  printf '%s' "$ROWS" | awk -F"$TAB" -v op="$1" '$1 == op { print $2; exit }'
}

derive
assert_eq "removal $(state worktree-agent-abcR), update $(state worktree-agent-abcU)" 'removal on, update skip'

deselect_op worktree-agent-abcR
derive
assert_eq "removal $(state worktree-agent-abcR), update $(state worktree-agent-abcU)" 'removal off, update off'
