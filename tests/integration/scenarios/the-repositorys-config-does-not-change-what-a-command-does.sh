#!/bin/sh
# The repository's own config asks for the settings the commands pin, and the
# commands still do only what their plan says.
#
#   rebase.updateRefs  would move a branch pointing into the replayed range
#   merge.autoStash    would set a dirty tree aside, fast-forward, and put the
#                      changes back, where git otherwise refuses
#   rebase.autoStash   the same for a rebase. Set, but no command reaches a
#                      rebase with tracked changes (each refuses or stashes
#                      first), so nothing here can show it being overridden.
#
# Set in the repository rather than globally because that is the config the
# pins have to beat that a container has: there is no global file here.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo
git config rebase.updateRefs true
git config rebase.autoStash true
git config merge.autoStash true

# feat: two commits of its own, published, checked out in a worktree.
# other: a local branch on feat's first commit, unpublished and checked out
# nowhere, so it is not live and that commit is in feat's replayed range.
branch feat
commit F1 f1.txt
git branch other
commit F2 f2.txt
git push -q -u origin feat
git switch -q main
worktree_for feat

# The trunk moves on origin, so feat has something to bring in.
commit T1 t.txt
git push -q origin main
git fetch -q origin

other_before=$(git rev-parse refs/heads/other)

run_command git-spread --apply

echo '--- outcome: updateRefs ---'

carries refs/heads/feat t.txt
printf '  ok   feat was rebased\n'
[ "$(git rev-parse refs/heads/other)" = "$other_before" ] ||
  fail 'other moved with the rebase, which the plan never showed'
printf '  ok   other did not move\n'

# Origin's trunk moves on with a change to t.txt, and the local trunk has t.txt
# edited in its working tree. git catchup fast-forwards the trunk, and git
# refuses a fast-forward over a file it would overwrite.
git switch -q -c pusher main
printf 'T2\n' > t.txt
git commit -qam T2
git push -q origin pusher:main
git switch -q main
git branch -q -D pusher
git fetch -q origin
printf 'mine\n' > t.txt
dirty_before=$(cat t.txt)
main_before=$(git rev-parse refs/heads/main)

run_command git-catchup --apply

echo '--- outcome: autoStash ---'

[ "$(git rev-parse refs/heads/main)" = "$main_before" ] ||
  fail 'main moved under a dirty tree, so the fast-forward was not refused'
printf '  ok   main did not move\n'
[ "$(cat t.txt)" = "$dirty_before" ] || fail 'the edited file was changed'
printf '  ok   the edited file is as it was\n'
[ -z "$(git stash list)" ] || fail 'a stash entry was left behind'
printf '  ok   nothing was stashed\n'

echo 'PASS the-repositorys-config-does-not-change-what-a-command-does'
