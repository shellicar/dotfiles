#!/bin/sh
# git gc expires reflog entries older than gc.reflogExpire, 90 days by default,
# so an agent branch whose only entry is its creation, 100 days ago, has no
# reflog left afterwards and no creation date. In a repository that logs ref
# updates, as one git init made with a working tree does, a missing date can
# only mean that, so git refresh counts the branch as old and starts its
# removal ticked.
#
# A branch created 3 days ago keeps its entry through the gc and stays unticked,
# so the tick is the missing date and not every agent branch.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

now=$(date +%s)
day=86400
commit T t.txt
git push -q origin main
git fetch -q origin

# git init writes core.logAllRefUpdates=true into a repository with a working
# tree, so this is the setting a repository gets without anyone choosing it.
[ "$(git config --get core.logAllRefUpdates || :)" = true ] ||
  fail "core.logAllRefUpdates is [$(git config --get core.logAllRefUpdates || :)], not what git init writes"

t=$((now - 100 * day))
GIT_COMMITTER_DATE="@$t +0000" git worktree add -q -b worktree-agent-ancient "$ROOT/wt-ancient" main
t=$((now - 3 * day))
GIT_COMMITTER_DATE="@$t +0000" git worktree add -q -b worktree-agent-recent "$ROOT/wt-recent" main

reflog() { git reflog --no-show-signature --date=unix --format=%gd "refs/heads/$1"; }

[ -n "$(reflog worktree-agent-ancient)" ] ||
  fail 'worktree-agent-ancient has no reflog before the gc, so this proves nothing'
git gc -q
[ -z "$(reflog worktree-agent-ancient)" ] ||
  fail "git gc left worktree-agent-ancient a reflog: [$(reflog worktree-agent-ancient)]"
printf '  ok   git gc expired the reflog of worktree-agent-ancient\n'
[ -n "$(reflog worktree-agent-recent)" ] ||
  fail 'git gc expired the reflog of worktree-agent-recent too'
printf '  ok   worktree-agent-recent keeps its reflog\n'

status=0
out=$("$BIN/git-refresh" --plan --no-fetch 2>&1) || status=$?
printf '%s\n' "$out" | sed 's/^/  /'
[ "$status" = 0 ] || fail "git refresh exited $status"

removal_row() {
  printf '%s\n' "$out" | grep -E "remove $1( |\$)" | head -1 | sed 's/^ *//'
}

row=$(removal_row worktree-agent-ancient)
case "$row" in
  '[x]'*'agent branch with an expired reflog'*) printf '  ok   worktree-agent-ancient starts ticked\n' ;;
  *) fail "worktree-agent-ancient: expected its removal ticked for an expired reflog, got [$row]" ;;
esac

row=$(removal_row worktree-agent-recent)
case "$row" in
  '[ ]'*) printf '  ok   worktree-agent-recent starts unticked\n' ;;
  *) fail "worktree-agent-recent: expected its removal unticked, got [$row]" ;;
esac

echo 'PASS an-agent-branch-past-reflog-expiry-starts-ticked'
