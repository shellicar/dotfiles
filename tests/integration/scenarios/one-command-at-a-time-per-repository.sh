#!/bin/sh
# The commands share scratch files with fixed names in the repository's
# cleanup-cache, so only one runs at a time: a lock folder there, holding the
# owner's pid. Run with the real commands:
#   - a second command is refused while a live process holds the lock, and the
#     holder's lock survives that;
#   - a lock left by a dead process is taken over, and said so;
#   - the lock is gone after a normal run, and after the stop on a merge-tree
#     error.
set -eu

# The path exists only inside the container, where run.sh mounts it.
# shellcheck source=../lib.sh
. /scenario/lib.sh

new_repo

branch feature
commit F1 f.txt
git switch -q main
worktree_for feature
commit T1 t.txt
git push -q origin main
git fetch -q origin

LOCK=$(git rev-parse --git-common-dir)/cleanup-cache/lock
mkdir -p "$(dirname "$LOCK")"

# A live holder: a process that sleeps, recorded as git spread.
sleep 30 &
holder=$!
mkdir "$LOCK"
echo "$holder" > "$LOCK/pid"
echo 'git spread' > "$LOCK/command"

status=0
out=$("$BIN/git-refresh" --plan --no-fetch 2>&1) || status=$?
printf '%s\n' "$out" | sed 's/^/  /'
[ "$status" != 0 ] || fail 'git refresh ran while another command held the lock'
case "$out" in
  *"git refresh: git spread (pid $holder) is already running in this repo"*) printf '  ok   refused, naming the holder\n' ;;
  *) fail 'the refusal does not name the holder' ;;
esac
[ "$(cat "$LOCK/pid")" = "$holder" ] || fail "the holder's lock did not survive the refusal"
printf '  ok   the holder keeps its lock\n'

# The holder dies without releasing it.
kill "$holder"
wait "$holder" 2>/dev/null || :

out=$("$BIN/git-refresh" --plan --no-fetch 2>&1) || fail 'git refresh failed after the holder died'
case "$out" in
  *"taking over the lock left by git spread (pid $holder), which is no longer running"*)
    printf '  ok   the dead holder lock was taken over, and said so\n' ;;
  *) fail 'the takeover was not said' ;;
esac
[ -e "$LOCK" ] && fail 'the lock survived a normal run'
printf '  ok   no lock after a normal run\n'

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
printf '%s\n' "$out" | sed 's/^/  /'
case "$out" in
  *'git merge-tree failed'*) printf '  ok   stopped on the merge-tree error, exit %s\n' "$status" ;;
  *) fail 'the simulated merge-tree failure did not stop the command' ;;
esac
[ "$status" != 0 ] || fail 'the stop exited 0'
[ -e "$LOCK" ] && fail 'the lock survived the stop on a merge-tree error'
printf '  ok   no lock after the stop\n'

echo 'PASS one-command-at-a-time-per-repository'
