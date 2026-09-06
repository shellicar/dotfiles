#!/bin/sh
# run_update for real: a fast-forward, a merge, and a rebase that force-pushes.
# Nothing else runs any of them, and the force-push is the most consequential
# thing any of these commands do.
set -eu

. /scenario/lib.sh

new_repo

# rebased: own work, tracks its remote, and will be replayed onto the new trunk.
branch rebased
commit R1 r.txt
git push -q -u origin rebased
git switch -q main
worktree_for rebased

# merger: has already merged the trunk once, so it merges again rather than
# being rebased. Its push is an ordinary one.
git switch -q -c merger main
commit M1 m.txt
git push -q -u origin merger
git switch -q main
commit T1 t.txt
git push -q origin main
git switch -q merger
git merge -q --no-edit main
git push -q
git switch -q main
worktree_for merger

# The trunk moves again, so every worktree is behind.
commit T2 t2.txt
git push -q origin main
git fetch -q origin

rebased_before=$(git rev-parse refs/heads/rebased)

run_command git-spread --apply

echo '--- outcome ---'

# The rebase replayed onto the new trunk, so the branch moved and carries both
# its own work and the trunk's.
[ "$(git rev-parse refs/heads/rebased)" = "$rebased_before" ] &&
  fail 'rebased did not move'
printf '  ok   rebased moved\n'
carries refs/heads/rebased r.txt
carries refs/heads/rebased t2.txt

# And the force-push landed, so the remote agrees.
[ "$(git rev-parse refs/heads/rebased)" = "$(git rev-parse refs/remotes/origin/rebased)" ] ||
  fail 'the force-push did not reach the remote'
printf '  ok   remote matches after the force-push\n'

# The merge kept its own history and took the trunk in.
carries refs/heads/merger m.txt
carries refs/heads/merger t2.txt

echo 'PASS spread-applies-its-plan'
