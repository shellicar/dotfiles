#!/bin/sh
# git refresh starts the removal of an empty worktree-agent-* branch ticked,
# with a worktree or without one, unless the worktree stops it. A lock or
# uncommitted changes make the removal unavailable, and ignored files leave it
# unticked. An empty branch with any other name starts unticked. Every branch
# is made just before git refresh runs.
#
#   worktree-agent-clean      a worktree with nothing in it       [x]
#   worktree-agent-nowt       no worktree                         [x]
#   worktree-agent-locked     a locked worktree                   [-]
#   worktree-agent-staged     a staged file                       [-]
#   worktree-agent-unstaged   a tracked file changed              [-]
#   worktree-agent-untracked  an untracked file                   [-]
#   worktree-agent-ignored    an ignored file                     [ ], the file
#                                                                 listed under it
#   feature/empty             a worktree with nothing in it       [ ]
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

printf '.env\n' > .gitignore
git add .gitignore
git commit -qm 'ignore .env'
git push -q origin main
git fetch -q origin

agent() { git worktree add -q -b "worktree-agent-$1" "$ROOT/wt-agent-$1" main; }

agent clean
git branch worktree-agent-nowt main
agent locked
git worktree lock --reason 'claude agent agent-locked (pid 4242)' "$ROOT/wt-agent-locked"
agent staged
printf 'staged\n' > "$ROOT/wt-agent-staged/staged.txt"
git -C "$ROOT/wt-agent-staged" add staged.txt
agent unstaged
printf 'changed\n' > "$ROOT/wt-agent-unstaged/a.txt"
agent untracked
printf 'untracked\n' > "$ROOT/wt-agent-untracked/untracked.txt"
agent ignored
printf 'not a real setting\n' > "$ROOT/wt-agent-ignored/.env"
git worktree add -q -b feature/empty "$ROOT/wt-feature-empty" main

status=0
out=$("$BIN/git-refresh" --plan --no-fetch 2>&1) || status=$?
printf '%s\n' "$out" | sed 's/^/  /'
[ "$status" = 0 ] || fail "git refresh exited $status"

# expect <branch> <mark> <action> <reason>: the plan's row for removing the
# branch starts with the mark, has the action just before its [n ahead, age],
# and ends with the reason.
expect() {
  row=$(printf '%s\n' "$out" | grep -E "remove $1( |\$)" | head -1 | sed 's/^ *//')
  case "$row" in
    "$2"*"$3 ["*"  $4") printf '  ok   %s: %s ... %s\n' "$1" "$2" "$4" ;;
    *) fail "$1: expected [$2 ... $3 ... $4], got [$row]" ;;
  esac
}

expect worktree-agent-clean '[x]' 'remove worktree-agent-clean and its worktree' \
  'never diverged from main, agent branch'
expect worktree-agent-nowt '[x]' 'remove worktree-agent-nowt' \
  'never diverged from main, agent branch'
expect worktree-agent-locked '[-]' 'remove worktree-agent-locked and its worktree' \
  'never diverged from main, locked: claude agent agent-locked (pid 4242)'
for b in staged unstaged untracked; do
  expect "worktree-agent-$b" '[-]' "remove worktree-agent-$b and its worktree" \
    'never diverged from main, worktree has uncommitted changes'
done
expect worktree-agent-ignored '[ ]' 'remove worktree-agent-ignored and its worktree' \
  'never diverged from main'
# The unticked row says why: the line under it lists the ignored entries.
under=$(printf '%s\n' "$out" | awk '/remove worktree-agent-ignored / { getline; print; exit }' | sed 's/^ *//')
case "$under" in
  '↳ also deletes 1 ignored entries: .env') printf '  ok   worktree-agent-ignored: %s\n' "$under" ;;
  *) fail "worktree-agent-ignored: expected its ignored entries under the row, got [$under]" ;;
esac
expect feature/empty '[ ]' 'remove feature/empty and its worktree' \
  'never diverged from main'

echo 'PASS an-empty-agent-branch-starts-ticked-unless-its-worktree-stops-it'
