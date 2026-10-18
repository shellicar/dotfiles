#!/bin/sh
# git refresh starts the removal of an empty worktree-agent-* branch ticked once
# the branch was created 7 or more days ago. The pure suite fakes the reflog it
# reads that from; this runs the command against real branches, so the age it
# acts on is the one git records.
#
# Two branches make the age and the commit date disagree:
#
#   worktree-agent-old   created 8 days ago, at a commit made today
#   worktree-agent-new   created 1 day ago, at a commit made 100 days ago
#
# Read by creation, the old one starts ticked and the new one does not. Read by
# commit date, it would be the other way round.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

now=$(date +%s)
day=86400
long_ago=$((now - 100 * day))

printf 'old\n' > old.txt
git add old.txt
GIT_AUTHOR_DATE="@$long_ago +0000" GIT_COMMITTER_DATE="@$long_ago +0000" \
  git commit -qm 'dated 100 days ago'
old_commit=$(git rev-parse HEAD)
commit T t.txt
git push -q origin main
git fetch -q origin

t=$((now - 8 * day))
GIT_COMMITTER_DATE="@$t +0000" git worktree add -q -b worktree-agent-old "$ROOT/wt-agent-old" main
t=$((now - 1 * day))
GIT_COMMITTER_DATE="@$t +0000" git worktree add -q -b worktree-agent-new "$ROOT/wt-agent-new" "$old_commit"

status=0
out=$("$BIN/git-refresh" --plan --no-fetch 2>&1) || status=$?
printf '%s\n' "$out" | sed 's/^/  /'
[ "$status" = 0 ] || fail "git refresh exited $status"

# removal_row <branch>: the plan's row for removing it, its mark first.
removal_row() {
  printf '%s\n' "$out" | grep -E "remove $1( |\$)" | head -1 | sed 's/^ *//'
}

row=$(removal_row worktree-agent-old)
case "$row" in
  '[x]'*'agent worktree created 7+ days ago'*) printf '  ok   worktree-agent-old starts ticked, aged 7+ days\n' ;;
  *) fail "worktree-agent-old: expected its removal ticked and aged 7+ days, got [$row]" ;;
esac

row=$(removal_row worktree-agent-new)
case "$row" in
  '[ ]'*'agent worktree created'*) fail "worktree-agent-new: aged 7+ days though created 1 day ago: [$row]" ;;
  '[ ]'*) printf '  ok   worktree-agent-new starts unticked\n' ;;
  *) fail "worktree-agent-new: expected its removal unticked, got [$row]" ;;
esac

echo 'PASS an-agent-branch-is-aged-by-its-creation-not-its-commit'
