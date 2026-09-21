#!/bin/sh
# A branch with a colleague's commits on it is not rebased and force-pushed by
# git spread --apply, while a branch of your own beside it still is. Asserted on
# both the local branch and the remote, because the remote is what the
# colleague sees.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

# theirs: checked out to review, every commit by someone else.
branch theirs
GIT_AUTHOR_EMAIL=them@example.com commit T1 their.txt
git push -q -u origin theirs
git switch -q main
worktree_for theirs

# mine: own work, so it is still rebased, which shows the run did act.
branch mine
commit M1 mine.txt
git push -q -u origin mine
git switch -q main
worktree_for mine

commit A2 a2.txt
git push -q origin main
git fetch -q origin

theirs_before=$(git rev-parse refs/heads/theirs)
mine_before=$(git rev-parse refs/heads/mine)

run_command git-spread --apply

echo '--- outcome ---'

[ "$(git rev-parse refs/heads/theirs)" = "$theirs_before" ] || fail 'theirs was changed'
printf '  ok   theirs untouched\n'
[ "$(git rev-parse refs/remotes/origin/theirs)" = "$theirs_before" ] || fail 'theirs was pushed'
printf '  ok   origin/theirs untouched\n'

[ "$(git rev-parse refs/heads/mine)" = "$mine_before" ] && fail 'mine did not move'
printf '  ok   mine moved\n'
carries refs/heads/mine a2.txt

echo 'PASS spread-leaves-someone-elses-branch-alone'
