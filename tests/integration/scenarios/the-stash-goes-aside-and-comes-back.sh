#!/bin/sh
# The stash and the pop around an update, carried out for real.
#
# Whether a stash is needed is decided elsewhere and checked against git itself.
# This is the other half, which nothing else runs: that the work actually goes
# aside, that the update then happens at all, and that the work comes back.
#
# The failure it exists to catch is uncommitted changes sitting in the stash
# list instead of in the tree. Recoverable, but only once you know to look.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

# u.txt is the file the worktree will hold uncommitted changes to, and nothing
# the update brings in touches it. That is deliberate: a rebase refuses on ANY
# tracked change, related or not, so an unrelated one still needs the stash and
# still pops cleanly afterwards.
commit U u.txt
git push -q origin main

branch dirty
commit D d.txt
git push -q -u origin dirty
git switch -q main

# The trunk moves, so the worktree is behind and an update is on offer.
commit T t.txt
git push -q origin main
git fetch -q origin

worktree_for dirty
before=$(git rev-parse refs/heads/dirty)

printf 'work in progress\n' > "$ROOT/wt-dirty/u.txt"

run_command git-spread --apply --stash

echo '--- outcome ---'

[ "$(git rev-parse refs/heads/dirty)" = "$before" ] &&
  fail 'the branch did not move, so the update never happened and the rest proves nothing'
printf '  ok   the branch moved\n'
carries refs/heads/dirty d.txt
carries refs/heads/dirty t.txt

# The point of the whole thing: the uncommitted change is back where it was.
actual=$(cat "$ROOT/wt-dirty/u.txt")
[ "$actual" = 'work in progress' ] ||
  fail "the uncommitted change did not come back, u.txt now reads: $actual"
printf '  ok   the uncommitted change is back in the worktree\n'

# And it came back by being popped, not left in the list for you to find later.
cd "$ROOT/wt-dirty"
[ -z "$(git stash list)" ] || fail "the stash list still holds: $(git stash list)"
cd "$ROOT/repo"
printf '  ok   nothing was left in the stash list\n'

echo 'PASS the-stash-goes-aside-and-comes-back'
