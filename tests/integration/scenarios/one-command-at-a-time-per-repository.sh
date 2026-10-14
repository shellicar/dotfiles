#!/bin/sh
# The commands share scratch files with fixed names in the repository's
# cleanup-cache, so only one runs at a time: flock on cleanup-cache/lock.
# Run with the real commands and the real flock:
#   - a second command is refused while another process holds the lock, and
#     the message names the lock;
#   - the lock is free after a normal run, after a holder killed with SIGKILL,
#     and after the stop on a merge-tree error;
#   - a process git starts in the background does not keep the lock after the
#     command has exited.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

command -v flock >/dev/null 2>&1 || fail 'flock is not installed'

new_repo

branch feature
commit F1 f.txt
git switch -q main
worktree_for feature
commit T1 t.txt
git push -q origin main
git fetch -q origin

LOCK=$(git rev-parse --path-format=absolute --git-common-dir)/cleanup-cache/lock
mkdir -p "$(dirname "$LOCK")"

free() {
  flock -n "$LOCK" true || fail "the lock is still held $1"
  printf '  ok   the lock is free %s\n' "$1"
}

# A holder: another process with the lock. One process, not flock running a
# child, so SIGKILL to it leaves nothing else holding the descriptor.
sh -c 'exec 9>>"$1"; flock 9; exec sleep 30' sh "$LOCK" &
holder=$!
sleep 1

status=0
out=$("$BIN/git-refresh" --plan --no-fetch 2>&1) || status=$?
printf '%s\n' "$out" | sed 's/^/  /'
[ "$status" != 0 ] || fail 'git refresh ran while another process held the lock'
case "$out" in
  *"git refresh: another command is running in this repo (it holds $LOCK)"*) printf '  ok   refused, naming the lock\n' ;;
  *) fail 'the refusal does not name the lock' ;;
esac

kill -9 "$holder"
wait "$holder" 2>/dev/null || :
free 'after its holder was killed with SIGKILL'

"$BIN/git-refresh" --plan --no-fetch >/dev/null 2>&1 || fail 'git refresh failed'
free 'after a normal run'

# A git whose merge-tree fails, so the merge check stops the command.
mkdir -p "$ROOT/failing-git"
real=$(command -v git)
cat > "$ROOT/failing-git/git" <<EOF
#!/bin/sh
case "\$1" in merge-tree) echo "fatal: simulated failure" >&2; exit 128 ;; esac
exec $real "\$@"
EOF
chmod +x "$ROOT/failing-git/git"
# The run above cached its answers, and a cached answer never asks merge-tree.
rm -rf "$(dirname "$LOCK")/in-main"
status=0
out=$(PATH="$ROOT/failing-git:$PATH" "$BIN/git-refresh" --plan --no-fetch 2>&1) || status=$?
case "$out" in
  *'git merge-tree failed'*) printf '  ok   stopped on the merge-tree error, exit %s\n' "$status" ;;
  *) fail 'the simulated merge-tree failure did not stop the command' ;;
esac
[ "$status" != 0 ] || fail 'the stop exited 0'
free 'after the stop on a merge-tree error'

# A process git leaves running in the background, as an ssh connection master
# or a credential cache would, started from inside a command holding the lock.
cat > "$ROOT/background.sh" <<EOF
. /repo/home/common/lib/git-common.sh
TOOL='git refresh'
use_cache_dir
git -c 'alias.linger=!sleep 30 >/dev/null 2>&1 & echo \$! > $ROOT/linger.pid' linger
EOF
sh "$ROOT/background.sh"
kill -0 "$(cat "$ROOT/linger.pid")" 2>/dev/null || fail 'the background process is not running, so this proves nothing'
free 'after the command exited, with a process git started still running'
kill "$(cat "$ROOT/linger.pid")" 2>/dev/null || :

echo 'PASS one-command-at-a-time-per-repository'
