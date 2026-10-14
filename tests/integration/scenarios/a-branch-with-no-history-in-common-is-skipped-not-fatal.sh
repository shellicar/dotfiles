#!/bin/sh
# An orphan branch, a pages branch for instance, checked out in a worktree while
# main moves on. git merge-tree refuses to merge unrelated histories, and a git
# failure in the merge check stops a command, so the branch has to be answered
# before merge-tree is asked. git refresh, git spread and git cleanup must each
# finish and say the branch shares no history with main.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

git switch -q --orphan pages
commit P1 index.html
commit P2 index.html
git switch -q main
worktree_for pages

commit T1 t.txt
git push -q origin main
git fetch -q origin

git merge-base pages origin/main >/dev/null 2>&1 && fail 'pages shares history with main, so this proves nothing'
printf '  ok   pages shares no history with main\n'

check() {
  name=$1
  shift
  status=0
  out=$("$@" 2>&1) || status=$?
  printf '%s\n' "$out" | sed 's/^/  /'
  [ "$status" = 0 ] || fail "$name exited $status"
  case "$out" in
    *'merge-tree failed'*) fail "$name stopped on merge-tree" ;;
  esac
  printf '  ok   %s finished\n' "$name"
}

check 'git refresh' "$BIN/git-refresh" --plan --no-fetch
case "$out" in
  *'pages'*'shares no history with main'*) printf '  ok   git refresh says pages shares no history\n' ;;
  *) fail 'git refresh did not say pages shares no history with main' ;;
esac
check 'git spread' "$BIN/git-spread"
case "$out" in
  *'[pages]: shares no history with main'*) printf '  ok   git spread says pages shares no history\n' ;;
  *) fail 'git spread did not say pages shares no history with main' ;;
esac
check 'git cleanup' "$BIN/git-cleanup" --no-fetch -a

echo 'PASS a-branch-with-no-history-in-common-is-skipped-not-fatal'
