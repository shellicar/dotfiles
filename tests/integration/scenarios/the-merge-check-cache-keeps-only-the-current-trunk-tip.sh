#!/bin/sh
# The answers of the merge check are cached per trunk tip. Once the trunk moves,
# the old tip's answers are never read again, so the next run removes them and
# keeps the current tip's. Run for real, so the directory is the one the
# commands use: the repository's common git directory.
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

CACHE=$(git rev-parse --git-common-dir)/cleanup-cache/in-main
old=$(git rev-parse refs/remotes/origin/main)

"$BIN/git-refresh" --plan --no-fetch >/dev/null 2>&1 || fail 'the first git refresh failed'
[ -d "$CACHE/$old" ] || fail "no answers were cached for the tip $old"
printf '  ok   answers cached for the first tip\n'

commit T2 t2.txt
git push -q origin main
git fetch -q origin
new=$(git rev-parse refs/remotes/origin/main)

"$BIN/git-refresh" --plan --no-fetch >/dev/null 2>&1 || fail 'the second git refresh failed'
[ -e "$CACHE/$old" ] && fail 'the old tip answers survived the second run'
printf '  ok   the old tip answers are gone\n'
[ -d "$CACHE/$new" ] || fail 'no answers were cached for the current tip'
printf '  ok   the current tip answers are there\n'

echo 'PASS the-merge-check-cache-keeps-only-the-current-trunk-tip'
