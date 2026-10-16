#!/bin/sh
# The unit suite runs against tests/fake-git.sh, so its verdicts are only as
# good as the fake's answers. This builds one commit graph twice, in a real
# repository and in the fake, asks both the same questions, and fails on any
# answer that differs: output and exit status both.
#
# It covers these forms only: rev-list --count <a> ^<b>, including a side that
# names nothing; a commit's time (%ct); how long ago that was (%cr), across every
# unit git uses and either side of each boundary between them; and the time of a
# commit the fake's rebase makes. The fake's other forms, such as merge-base,
# a..b counts, for-each-ref and --not, are not checked against git here.
#
# A form added to the fake belongs here too, or nothing checks it against git.
set -eu

# The paths exist only inside the container, where run.sh mounts them.
# shellcheck source=../lib.sh
. /scenario/lib.sh

# set -e ends the scenario at the first command that fails, which says nothing
# on its own.
trap 'st=$?; [ "$st" = 0 ] || printf "FAIL the-fake-git-answers-as-git-does stopped with status %s\n" "$st" >&2' EXIT

# The clock both sides read: GIT_TEST_DATE_NOW for git, NOW for the fake.
CLOCK=1800000000
# When the rebase runs, an hour before the clock.
REBASED_AT=1799996400

mkdir -p "$ROOT"
IDS=$ROOT/ids
mkdir -p "$IDS"

# How far before the clock each dated commit is, in seconds. First the edges of
# each unit as git's date.c rounds them: seconds below 90, minutes below 5370,
# hours below 127770, days below 1164570, weeks below 6002970, months below
# 31490970, years with months below 157634970, years after. Then sweeps across
# minutes, hours and days, so a count that turns over inside a unit is checked
# as well as the unit changing. -60 is a commit dated after the clock.
DELTAS=$ROOT/deltas
for d in -60 0 1 2 59 60 89 90 91 149 150 \
         5369 5370 5371 127769 127770 127771 1164569 1164570 1164571 \
         6002969 6002970 6002971 31490969 31490970 31490971 \
         31536000 34300000 63072000 157634969 157634970 157634971 315360000; do
  printf '%s\n' "$d"
done > "$DELTAS"
i=120; while [ "$i" -le 7200 ]; do printf '%s\n' "$i"; i=$((i + 120)); done >> "$DELTAS"
i=3600; while [ "$i" -le 172800 ]; do printf '%s\n' "$i"; i=$((i + 3600)); done >> "$DELTAS"
i=1; while [ "$i" -le 400 ]; do printf '%s\n' $((i * 86400)); i=$((i + 3)); done >> "$DELTAS"
i=400; while [ "$i" -le 2500 ]; do printf '%s\n' $((i * 86400)); i=$((i + 15)); done >> "$DELTAS"

# The scenario's own names stay clear of the ones harness.sh and fake-git.sh
# set: sourcing them inside the subshell below would replace any it shares.
#
#   main      A - B - C - D
#   f              \ F1 - F2 - F3   3 of its own to main's 2, so a count
#                                   read the wrong way round differs
#   feature    \ X               rebased onto main as rebased
#   d<n>       \ one commit per delta, dated that long before the clock
GRAPH=$ROOT/graph
cat > "$GRAPH" <<EOF
A - $((CLOCK - 900000))
B A $((CLOCK - 800000))
C B $((CLOCK - 700000))
D C $((CLOCK - 600000))
F1 B $((CLOCK - 500000))
F2 F1 $((CLOCK - 400000))
F3 F2 $((CLOCK - 350000))
X A $((CLOCK - 300000))
EOF
n=0
while read -r d; do
  n=$((n + 1))
  printf 'd%s A %s\n' "$n" $((CLOCK - d)) >> "$GRAPH"
done < "$DELTAS"

REF_LIST=$ROOT/refs
{
  printf 'refs/heads/main D\nrefs/heads/f F3\nrefs/heads/feature X\n'
  i=1; while [ "$i" -le "$n" ]; do printf 'refs/heads/d%s d%s\n' "$i" "$i"; i=$((i + 1)); done
} > "$REF_LIST"

QUESTIONS=$ROOT/questions
{
  printf '%s\n' \
    'rev-list --count main ^f' \
    'rev-list --count f ^main' \
    'rev-list --count main ^main' \
    'rev-list --count main ^nosuch' \
    'rev-list --count nosuch ^f' \
    'rev-list --no-commit-header -1 --format=%ct f' \
    'rev-list --no-commit-header -1 --format=%ct rebased' \
    'rev-list --no-commit-header -1 --format=%cr rebased'
  i=1
  while [ "$i" -le "$n" ]; do
    printf 'rev-list --no-commit-header -1 --format=%%ct d%s\n' "$i"
    printf 'rev-list --no-commit-header -1 --format=%%cr d%s\n' "$i"
    i=$((i + 1))
  done
} > "$QUESTIONS"

# ask <command>: puts every question to the command, one answer per line: the
# question, what was printed, the exit status.
ask() {
  while read -r q; do
    set -f
    # shellcheck disable=SC2086
    set -- $q
    set +f
    out=$("$ASK" "$@" 2>/dev/null) && st=0 || st=$?
    printf '%s\t%s\t%s\n' "$q" "$(printf '%s' "$out" | tr '\n' ' ')" "$st"
  done < "$QUESTIONS"
}

# ── real git ────────────────────────────────────────────────────────────────
REAL=$ROOT/real
git init -q -b main "$REAL"
cd "$REAL"
git config user.email test@test
git config user.name test
git config commit.gpgsign false
empty=$(git hash-object -t tree -w --stdin </dev/null)
blob=$(printf 'x\n' | git hash-object -w --stdin)
withfile=$(printf '100644 blob %s\tx.txt\n' "$blob" | git mktree)
while read -r name parent when; do
  # X carries a file so that its rebase has something to replay.
  tree=$empty; [ "$name" = X ] && tree=$withfile
  if [ "$parent" = - ]; then
    id=$(GIT_COMMITTER_DATE="$when +0000" GIT_AUTHOR_DATE="$when +0000" git commit-tree "$tree" -m "$name")
  else
    id=$(GIT_COMMITTER_DATE="$when +0000" GIT_AUTHOR_DATE="$when +0000" git commit-tree "$tree" -p "$(cat "$IDS/$parent")" -m "$name")
  fi
  printf '%s\n' "$id" > "$IDS/$name"
done < "$GRAPH"
while read -r ref name; do
  git update-ref "$ref" "$(cat "$IDS/$name")"
done < "$REF_LIST"
git switch -q -c rebased refs/heads/feature || fail 'git refused: switch -q -c rebased refs/heads/feature'
GIT_COMMITTER_DATE="$REBASED_AT +0000" git rebase -q --onto main "$(cat "$IDS/A")" ||
  fail 'git refused: rebase -q --onto main A'

real_git() { GIT_TEST_DATE_NOW=$CLOCK git "$@"; }
ASK=real_git ask > "$ROOT/real.answers"

# ── the fake ────────────────────────────────────────────────────────────────
# In a subshell: the harness replaces git with a function, and the real git
# above must stay what it is.
(
  WORK=$ROOT/fake
  mkdir -p "$WORK"
  # shellcheck source=../../harness.sh
  . /repo/tests/harness.sh
  # shellcheck source=../../fake-git.sh
  . /repo/tests/fake-git.sh
  while read -r name parent when; do
    if [ "$parent" = - ]; then commit "$name"; else commit "$name" "$parent"; fi
    committed "$name" "$when"
  done < "$GRAPH"
  while read -r ref name; do
    ref_set "$ref" "$name"
  done < "$REF_LIST"
  NOW=$REBASED_AT
  git_says switch -q -c rebased refs/heads/feature ||
    fail 'the fake refused: switch -q -c rebased refs/heads/feature'
  git_says rebase -q --onto main A ||
    fail 'the fake refused: rebase -q --onto main A'
  NOW=$CLOCK
  ASK=git_says ask
) > "$ROOT/fake.answers" || fail 'the fake could not be set up; its reason is above'

total=$(wc -l < "$ROOT/real.answers")
if ! diff "$ROOT/real.answers" "$ROOT/fake.answers" > "$ROOT/differences"; then
  printf '  git (<) and the fake (>) answered differently:\n'
  sed 's/^/    /' "$ROOT/differences"
  fail "the fake does not answer as git does"
fi
printf '  ok   %s answers the same from git and the fake\n' "$total"

echo 'PASS the-fake-git-answers-as-git-does'
