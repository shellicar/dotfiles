#!/bin/sh
# Runs inside the container, against a repository built here.
#
# This is the half nothing else reaches: run_plan, remove_branch against a real
# worktree, and a real rescue rebase. The pure suite proves what the commands
# decide; only this proves that carrying it out does what the decision said.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

# landed: squash-merged, worktree attached. Both should go.
branch landed
commit L1 one.txt
commit L2 two.txt
squash_into_main landed
git switch -q main
worktree_for landed

# review: squash-merged, then one more commit. The extra must survive on
# rescue/review and the original must go.
branch review
commit R1 three.txt
squash_into_main review
commit R2 four.txt

# keep: unmerged, and cut from main rather than from review, or it inherits
# review's already-merged content and reads as merged itself.
git switch -q main
branch keep
commit K1 five.txt

git switch -q main

run_command git-cleanup --no-fetch --apply --rescue

echo '--- outcome ---'
gone refs/heads/landed
gone_dir "$ROOT/wt-landed"
gone refs/heads/review
exists refs/heads/rescue/review
exists refs/heads/keep

# The whole point of a rescue: the work that was not in main survived, and it is
# on the rescue branch rather than having quietly reached the trunk.
carries refs/heads/rescue/review four.txt
lacks refs/heads/main four.txt

echo 'PASS cleanup-applies-its-plan'
