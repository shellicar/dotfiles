#!/bin/sh
# The repository's own config asks for the branch and push settings the
# commands pin, and the commands still do only what their plan says.
#
#   branch.autoSetupMerge=always   rescue/<branch> would track the local branch
#                                  the rescue then deletes
#   branch.autoSetupMerge=false    the main git main recreates would have no
#                                  upstream
#   push.recurseSubmodules=on-demand
#                                  a force-push would also push the submodule's
#                                  commits, which no plan shows. Two pins stop
#                                  it: push.recurseSubmodules=no, and
#                                  submodule.recurse=false, which push reads as
#                                  the same switch, last one read winning. Only
#                                  with both removed does this part fail.
#
# And the other way: the submodule.recurse pin must not stop a fetch bringing
# in the submodule commits the trunk now points to, which git does by default.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

# review: squash-merged through its own pull request, then one more commit, so
# git cleanup rescues it.
branch review
commit R1 r1.txt
R1=$(git rev-parse HEAD)
squash_into_main review
SQUASH=$(git rev-parse refs/remotes/origin/main)
commit R2 r2.txt
git switch -q main

git config branch.autoSetupMerge always
# A rescue needs the branch's own merged pull request, and origin is a path
# with no host to ask. The command is sourced and the query answered with the
# pull request that squashed review: its source branch, its last commit, and
# the squash on main.
printf '%s\n' '--- git-cleanup --no-fetch --apply --rescue, with review'"'"'s pull request ---'
(
  # shellcheck source=../../../home/common/lib/git-common.sh
  . /repo/home/common/lib/git-common.sh
  # shellcheck source=../../../home/common/bin/git-cleanup
  . "$BIN/git-cleanup"
  fetch_pr_merges() {
    PR_MERGE_TABLE=$(printf 'review\t%s\t%s' "$R1" "$SQUASH")
    PR_SOURCE='from the scenario'; PR_HINT=''
  }
  main --no-fetch --apply --rescue
) 2>&1 | sed 's/^/  /'

echo '--- outcome: the rescue branch ---'
exists refs/heads/rescue/review
gone refs/heads/review
[ -z "$(git config --get branch.rescue/review.merge || :)" ] ||
  fail "rescue/review tracks $(git config --get branch.rescue/review.merge)"
printf '  ok   rescue/review tracks nothing\n'

# git main recreates a main that is missing locally.
git switch -q -c elsewhere
git branch -q -D main
git config branch.autoSetupMerge false
run_command git-main

echo '--- outcome: the recreated main ---'
[ "$(git symbolic-ref --short HEAD)" = main ] || fail 'git main did not switch to main'
[ "$(git config --get branch.main.merge || :)" = refs/heads/main ] ||
  fail 'the recreated main has no upstream'
printf '  ok   main tracks origin/main\n'
git config --unset branch.autoSetupMerge

# A submodule whose remote is a bare repository here.
git init -q --bare -b main "$ROOT/sub.git"
git init -q -b main "$ROOT/sub-seed"
( cd "$ROOT/sub-seed"
  git config user.email test@test; git config user.name test; git config commit.gpgsign false
  commit S0 s0.txt
  git push -q "$ROOT/sub.git" main )
git -c protocol.file.allow=always submodule add -q "$ROOT/sub.git" sub
git commit -qm 'add sub'
git push -q origin main

# bump: moves the submodule to a commit its remote does not have, and is
# published without it. The submodule's commit is on a branch of the same name,
# because on-demand pushes the submodule with the superproject's refspec, and
# without that branch the whole push fails rather than pushing it.
branch bump
( cd sub
  git config user.email test@test; git config user.name test; git config commit.gpgsign false
  git switch -q -c bump
  commit S1 s1.txt )
sub_commit=$(git -C sub rev-parse HEAD)
git add sub
git commit -qm 'bump sub'
git push -q -u origin bump

# The trunk moves without touching the submodule. Added by name, because the
# submodule's checkout stays on S1 across the switch.
git switch -q main
printf 'T1\n' > t.txt
git add t.txt
git commit -qm T1
git push -q origin main
git switch -q bump
git fetch -q origin

git config push.recurseSubmodules on-demand
run_command git-catchup --apply

echo '--- outcome: the submodule ---'
carries refs/remotes/origin/bump t.txt
printf '  ok   bump was rebased and pushed\n'
git -C "$ROOT/sub.git" cat-file -e "$sub_commit^{commit}" 2>/dev/null &&
  fail "the push also pushed the submodule commit $sub_commit"
printf '  ok   the submodule commit was not pushed\n'

# Fetching keeps git's default for submodules: the commits that new
# superproject commits point to are fetched into the submodule too. Pinning
# submodule.recurse=false switches that off unless fetch.recurseSubmodules
# puts it back. Someone else moves the submodule on the trunk.
( cd "$ROOT/sub-seed"
  commit S2 s2.txt
  git push -q "$ROOT/sub.git" main )
sub_next=$(git -C "$ROOT/sub-seed" rev-parse HEAD)
git clone -q "$ROOT/upstream.git" "$ROOT/other"
( cd "$ROOT/other"
  git config user.email test@test; git config user.name test; git config commit.gpgsign false
  git update-index --cacheinfo "160000,$sub_next,sub"
  git commit -qm 'move sub to S2'
  git push -q origin main )
# The submodule's own fetch is a local path, which git allows a submodule only
# when told to.
git -C sub config protocol.file.allow always

# git wt-create fetches before it creates the worktree.
run_command git-wt-create fetch-probe

echo '--- outcome: the submodule fetch ---'
git -C sub cat-file -e "$sub_next^{commit}" 2>/dev/null ||
  fail 'the fetch did not bring in the submodule commit the trunk now points to'
printf '  ok   the submodule commit the trunk points to was fetched\n'

echo 'PASS a-new-branch-and-a-push-carry-only-what-the-plan-says'
