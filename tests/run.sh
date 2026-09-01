#!/bin/sh
# Runs every case in tests/cases. Quiet on success; a failure prints the case
# and why. Exit 1 means a case failed, 64 means the run could not happen.
set -u

TESTS=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$TESTS/.." && pwd)
export TESTS REPO

[ -d "$TESTS/cases" ] || { echo "no cases directory" >&2; exit 64; }

failed=0
ran=0

for case_file in "$TESTS"/cases/*.sh; do
  [ -f "$case_file" ] || continue
  ran=$((ran + 1))
  name=$(basename "$case_file" .sh)

  # Each case gets its own shell and its own directory, so one cannot leak a
  # stubbed answer or a variable into the next.
  work=$(mktemp -d) || { echo "cannot make a working directory" >&2; exit 64; }
  out=$(WORK=$work sh "$case_file" 2>&1)
  status=$?
  rm -rf "$work"

  if [ "$status" -ne 0 ]; then
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$name"
    printf '%s\n' "$out" | sed 's/^/  /'
  fi
done

[ "$ran" -eq 0 ] && { echo "no cases found" >&2; exit 64; }

if [ "$failed" -ne 0 ]; then
  printf '\n%d of %d failed\n' "$failed" "$ran"
  exit 1
fi
exit 0
