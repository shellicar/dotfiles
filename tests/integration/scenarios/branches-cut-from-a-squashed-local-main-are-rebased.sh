#!/bin/sh
# Several branches cut from a local main holding commits nobody had pushed.
# Those commits then reach origin as two separate squash merges, and local main
# is reset to origin. Every branch still holds the old commits, whose work is
# all in main.
#
# git refresh offers each a rebase from its landed commit, the highest commit
# whose merge into main changes nothing. It must not offer a rescue, since none
# of these branches had a pull request of its own, and must not refuse them for
# sharing the old commits. One branch holds a merge with an edit of its own,
# which the rebase would drop: offered, but unticked and named. And a branch
# cut from another branch's unmerged work is still refused.
#
# Then git spread carries the rebases out, which runs the same rebase start the
# plan printed, and every rebased branch must end with the tree it had.
#
# It has to be real git: whether merging a commit into main changes nothing is
# git's answer (merge-tree), as is what a merge's own edits are (remerge-diff).
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

# Two commits on local main, never pushed. L2 changes the file L1 created, so
# L1 tested alone conflicts with main once both have landed: only L2 passes.
commit one f.txt
L1=$(git rev-parse HEAD)
commit two f.txt
L2=$(git rev-parse HEAD)

# p and r: one commit each. q: one commit, then a merge of a side branch in
# which a file was edited by hand before the merge was committed.
git switch -q -c p "$L2"
commit P1 p.txt
git switch -q -c r "$L2"
commit R1 r.txt
git switch -q -c side "$L2"
commit S1 s.txt
git switch -q -c q "$L2"
commit Q1 q.txt
git merge -q --no-ff --no-commit side
printf 'edited during the merge\n' > q.txt
git add q.txt
git commit -qm 'merge side into q'
MERGE=$(git rev-parse --short HEAD)
# feature/a: work of its own on the old commits. feature/b: cut from feature/a.
git switch -q -c feature/a "$L2"
commit X1 x.txt
git switch -q -c feature/b
commit Y1 y.txt

# The two commits land on origin as separate squashes, under new commits.
git switch -q -c land origin/main
git checkout -q "$L1" -- f.txt
git commit -qm 'squash of one'
git checkout -q "$L2" -- f.txt
git commit -qm 'squash of two'
git push -q origin land:main
git fetch -q origin
git switch -q main
git reset -q --hard origin/main
git branch -q -D land side

for b in p q r feature/a feature/b; do worktree_for "$b"; done

# Preconditions, or the case could pass for the wrong reason.
git merge-base --is-ancestor "$L2" origin/main && fail 'L2 is in main by ancestry, so nothing is tested'
[ "$(git merge-tree --write-tree origin/main "$L2" | head -1)" = "$(git rev-parse 'origin/main^{tree}')" ] ||
  fail 'L2 does not pass the check, so the layout is not the one described'
printf '  ok   L2 passes the check\n'
if [ "$(git merge-tree --write-tree origin/main "$L1" 2>/dev/null | head -1)" = "$(git rev-parse 'origin/main^{tree}')" ]; then
  fail 'L1 passes the check too, so the walk stopping at the first pass is not tested'
fi
printf '  ok   L1 alone fails the check\n'
[ -n "$(git show --remerge-diff --format= --name-only "$MERGE")" ] || fail "merge $MERGE carries no edit of its own"
printf '  ok   merge %s carries an edit of its own\n' "$MERGE"

out=$("$BIN/git-refresh" --plan --no-fetch 2>&1) || fail 'git refresh --plan failed'
printf '%s\n' "$out" | sed 's/^/  /'

has() {
  printf '%s\n' "$out" | grep -F -- "$1" >/dev/null || fail "missing from the plan: $1"
  printf '  ok   %s\n' "$1"
}

has '[x]   🔁 rebase p onto main'
has 'rebase p onto main [3 ahead'
has '[x]   🔁 rebase r onto main'
has '[x]   🔁 rebase feature/a onto main'
has '[ ]   🔁 rebase q onto main'
has "drops merge $MERGE edited q.txt"
has 'shares history with feature/a past main'

case "$out" in
  *rescue*) fail 'a rescue was offered, but none of these branches had a pull request of its own' ;;
esac
printf '  ok   no rescue offered\n'
case "$out" in
  *'shares history with p'*|*'shares history with q'*|*'shares history with r'*)
    fail 'refused over the old commits, whose work is in main' ;;
esac
printf '  ok   nothing refused over the landed commits\n'

# Each branch's tip and tree before anything runs: branch, tip, tree.
BEFORE=$ROOT/before
for b in p r feature/a q feature/b; do
  printf '%s %s %s\n' "$b" "$(git rev-parse "refs/heads/$b")" "$(git rev-parse "refs/heads/$b^{tree}")"
done > "$BEFORE"

run_command git-spread --apply

echo '--- outcome ---'
while read -r b before tree; do
  case "$b" in
    q|feature/b)
      [ "$(git rev-parse "refs/heads/$b")" = "$before" ] || fail "$b was changed, and should have been skipped"
      printf '  ok   %s left as it was\n' "$b"
      ;;
    *)
      [ "$(git rev-parse "refs/heads/$b")" = "$before" ] && fail "$b did not move"
      [ "$(git rev-parse "refs/heads/$b^{tree}")" = "$tree" ] || fail "$b's tree changed in the rebase"
      [ "$(git rev-list --count "origin/main..refs/heads/$b")" = 1 ] || fail "$b replayed more than its own commit"
      git merge-base --is-ancestor origin/main "refs/heads/$b" || fail "$b is not on main"
      printf '  ok   %s rebased onto main, its one commit replayed, tree unchanged\n' "$b"
      ;;
  esac
done < "$BEFORE"

echo 'PASS branches-cut-from-a-squashed-local-main-are-rebased'
