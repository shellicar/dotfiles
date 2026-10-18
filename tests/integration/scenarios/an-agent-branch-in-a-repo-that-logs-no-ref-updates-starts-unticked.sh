#!/bin/sh
# With core.logAllRefUpdates=false git writes no reflog for a new branch, so an
# agent branch has no creation date from the start. Its age is then unknown,
# and git refresh leaves its removal unticked.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

commit T t.txt
git push -q origin main
git fetch -q origin

git config core.logAllRefUpdates false
git worktree add -q -b worktree-agent-unlogged "$ROOT/wt-unlogged" main

st=0
out=$(git reflog --no-show-signature --date=unix --format=%gd refs/heads/worktree-agent-unlogged) || st=$?
[ -z "$out" ] || fail "worktree-agent-unlogged has a reflog, so this proves nothing: [$out]"
[ "$st" = 0 ] || fail "reading a branch with no reflog exited $st"
printf '  ok   worktree-agent-unlogged has no reflog, and reading it succeeds\n'

status=0
plan=$("$BIN/git-refresh" --plan --no-fetch 2>&1) || status=$?
printf '%s\n' "$plan" | sed 's/^/  /'
[ "$status" = 0 ] || fail "git refresh exited $status"

row=$(printf '%s\n' "$plan" | grep -E 'remove worktree-agent-unlogged( |$)' | head -1 | sed 's/^ *//')
case "$row" in
  '[ ]'*) printf '  ok   worktree-agent-unlogged starts unticked\n' ;;
  *) fail "worktree-agent-unlogged: expected its removal unticked, got [$row]" ;;
esac

echo 'PASS an-agent-branch-in-a-repo-that-logs-no-ref-updates-starts-unticked'
