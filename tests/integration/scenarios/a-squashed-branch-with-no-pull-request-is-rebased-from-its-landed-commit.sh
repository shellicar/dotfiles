#!/bin/sh
# A branch whose older work was squashed into main, with a commit still on top,
# and no pull request to say the branch's own pull request merged: the squash
# here is made by hand, and origin is a path with no pull request host.
#
# It gets a rebase from its landed commit, the squashed commit, which replays
# only the commit on top. A rebase from where it was cut would replay the
# squashed commit as well, onto a main that already has its content. A rescue
# is offered only when the branch's own pull request merged, which here
# nothing can say.
#
# It has to be a real repository, because whether the squashed commit's work is
# in main is git's answer (merge-tree), and a squash merge is the only thing
# that produces the shape.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

branch review
commit R1 r.txt
git push -q -u origin review

# Landed by content under a single new commit, with none of its own commits in
# main.
squash_into_main review

# Still one of its own on top, and the trunk moves again so an update is on
# offer at all.
commit R2 r2.txt
git switch -q main
commit T1 t.txt
git push -q origin main
git fetch -q origin
worktree_for review

# Without these the case could pass for the wrong reason: no rebase is offered
# for a branch that is level with the trunk either.
behind=$(git rev-list --count review..refs/remotes/origin/main)
[ "$behind" -gt 0 ] || fail 'review is not behind the trunk, so nothing would be offered anyway'
printf '  ok   review is %s behind, so an update would be on offer\n' "$behind"

out=$("$BIN/git-refresh" --plan --no-fetch 2>&1) || fail 'git refresh --plan failed'
printf '%s\n' "$out" | sed 's/^/  /'

case "$out" in
  *'rebase review onto main'*'replays 1'*)
    printf '  ok   the rebase replays only the commit on top\n' ;;
  *) fail 'no rebase replaying one commit was offered' ;;
esac

case "$out" in
  *'rescue'*) fail 'a rescue was offered with no pull request of the branch own merged' ;;
  *) printf '  ok   no rescue was offered\n' ;;
esac

echo 'PASS a-squashed-branch-with-no-pull-request-is-rebased-from-its-landed-commit'
