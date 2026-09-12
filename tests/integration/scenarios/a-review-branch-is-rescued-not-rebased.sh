#!/bin/sh
# A branch whose older work was squashed into main, with a commit still on top,
# gets the rescue and must not get a rebase.
#
# A rebase replays from the fork point, which includes the commits the squash
# already landed. Git cannot tell they landed, because a squash commit has a
# different patch id from the commits it flattened, so it applies them again on
# top of a main that already has that content and force-pushes the result. The
# rescue is the operation that carries such a branch forward: it replays only
# what is above the join point.
#
# It has to be a real repository, because the class is decided by walking the
# branch and hashing its cumulative diff against main's own commit diffs, and a
# squash merge is the only thing that produces the shape.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

branch review
commit R1 r.txt
git push -q -u origin review

# Landed by content under a single new commit, with none of its own commits in
# main. This is what makes the branch a review branch rather than a merged one.
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
  *'merged, 1 commit on top not in main'*)
    printf '  ok   classed as merged with one commit on top\n' ;;
  *) fail 'not classed as a review branch, so this case proves nothing' ;;
esac

case "$out" in
  *'rescue 1 off review'*) printf '  ok   the rescue is offered\n' ;;
  *) fail 'no rescue was offered, which is the only way this branch moves forward' ;;
esac

case "$out" in
  *'rebase review onto main'*)
    fail 'a rebase was offered, which replays the squashed commits back onto main' ;;
  *) printf '  ok   no rebase was offered\n' ;;
esac

echo 'PASS a-review-branch-is-rescued-not-rebased'
