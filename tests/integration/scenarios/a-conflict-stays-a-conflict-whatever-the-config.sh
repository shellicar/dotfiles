#!/bin/sh
# The repository's own config asks git to settle conflicts by itself, and the
# commands' merges and rebases still stop on them, the way their plan expects.
#
#   branch.<name>.mergeOptions=-Xtheirs  a merge takes the trunk's side of a
#                                        conflicting edit
#   merge.directoryRenames=true          a file added in a directory the trunk
#                                        renamed is moved into the new name
#   merge.renormalize=true               an edit to a file the trunk converted
#                                        to LF line endings goes through
#   branch.<name>.mergeOptions=--squash  a fast-forward stages the trunk's
#                                        changes and leaves the branch behind
#   merge.renames=false                  the opposite direction: a rename on the
#                                        trunk and an edit on the branch becomes
#                                        a conflict where git would carry it over
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

printf 'base\n' > f.txt
mkdir dir
printf 'a\n' > dir/a.txt
seq 1 20 > old.txt
printf 'one\r\ntwo\r\nthree\r\n' > crlf.txt
git add f.txt dir/a.txt old.txt crlf.txt
git commit -qm base
git push -q origin main

# merger: has merged the trunk before, so it is updated by merging again. Its
# own edit to f.txt conflicts with the trunk's.
branch merger
commit M1 m.txt
git push -q -u origin merger
git switch -q main
commit T1 t.txt
git push -q origin main
git switch -q merger
git merge -q --no-edit main
printf 'merger\n' > f.txt
git commit -qam 'merger edits f'
git push -q

# The other three are rebased.
git switch -q -c dirmove main
printf 'new\n' > dir/new.txt
git add dir/new.txt
git commit -qm 'add dir/new.txt'
git push -q -u origin dirmove

git switch -q -c crlf main
printf 'one\r\nTWO\r\nthree\r\n' > crlf.txt
git commit -qam 'crlf edits line two'
git push -q -u origin crlf

git switch -q -c renamed main
sed 's/^5$/five/' old.txt > old.tmp && mv old.tmp old.txt
git commit -qam 'renamed edits line five'
git push -q -u origin renamed

# behind: nothing of its own, so it is fast-forwarded.
git branch -q behind main

# The trunk moves under all five.
git switch -q main
printf 'main\n' > f.txt
git mv dir b
printf '* text=auto\n' > .gitattributes
git add f.txt .gitattributes
git add --renormalize .
git mv old.txt new.txt
git commit -qm 'trunk: f, dir renamed, line endings, old.txt renamed'
git push -q origin main
git fetch -q origin

for b in merger dirmove crlf renamed behind; do worktree_for "$b"; done
merger_before=$(git rev-parse refs/heads/merger)
dirmove_before=$(git rev-parse refs/heads/dirmove)
crlf_before=$(git rev-parse refs/heads/crlf)
renamed_before=$(git rev-parse refs/heads/renamed)

git config branch.merger.mergeOptions -Xtheirs
git config branch.behind.mergeOptions --squash
git config merge.directoryRenames true
git config merge.renormalize true
git config merge.renames false

run_command git-spread --apply

echo '--- outcome: git spread ---'
[ "$(git rev-parse refs/heads/merger)" = "$merger_before" ] ||
  fail "merger was merged; f.txt is now: $(git show refs/heads/merger:f.txt)"
printf '  ok   merger stopped on the conflict and is untouched\n'
[ "$(git rev-parse refs/heads/dirmove)" = "$dirmove_before" ] ||
  fail "dirmove was rebased; its files: $(git ls-tree -r --name-only refs/heads/dirmove | tr '\n' ' ')"
printf '  ok   dirmove stopped on the directory rename and is untouched\n'
[ "$(git rev-parse refs/heads/crlf)" = "$crlf_before" ] ||
  fail 'crlf was rebased over the line-ending conversion'
printf '  ok   crlf stopped on the line-ending conflict and is untouched\n'
[ "$(git rev-parse refs/heads/renamed)" != "$renamed_before" ] ||
  fail 'renamed was not rebased, so the rename was not carried over'
[ "$(git show refs/heads/renamed:new.txt | sed -n 5p)" = five ] ||
  fail 'renamed does not carry its edit into new.txt'
printf '  ok   renamed was rebased and its edit follows the rename\n'
[ "$(git rev-parse refs/heads/behind)" = "$(git rev-parse refs/remotes/origin/main)" ] ||
  fail 'behind was not fast-forwarded to the trunk'
[ -z "$(git -C "$ROOT/wt-behind" status --porcelain)" ] ||
  fail 'the fast-forward left changes staged in behind'
printf '  ok   behind was fast-forwarded and left clean\n'

# git catchup merges with its own call, so it is checked on its own.
cd "$ROOT/wt-merger"
run_command git-catchup --apply

echo '--- outcome: git catchup ---'
[ "$(git rev-parse refs/heads/merger)" = "$merger_before" ] ||
  fail "git catchup merged merger; f.txt is now: $(git show refs/heads/merger:f.txt)"
printf '  ok   merger stopped on the conflict and is untouched\n'
git merge --abort 2>/dev/null || :

echo 'PASS a-conflict-stays-a-conflict-whatever-the-config'
