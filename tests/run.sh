#!/bin/sh
# Runs every case in tests/cases, once under each shell below. On success it
# prints two lines: the shells it ran under and the count. A failure also prints
# the case, the shell it failed under, and why. Exit 1 means a case failed, 64
# means the run could not happen.
#
# The shells: sh, whatever this machine has, and bash in POSIX mode. On macOS sh
# is bash 3.2 in POSIX mode, so there the first run is the Mac's own shell. On
# Linux sh is usually dash, and the bash run is the nearest stand-in for the Mac
# that the machine has: a newer bash, so it can pass where bash 3.2 would fail.
# The summary names each shell, by its version where it has one and otherwise by
# its path, so a run claims only what it ran.
#
# The shell is the one the case file runs under, and what it sources. A case
# that starts the command it tests as a program, by its path or with sh, tests
# that command under sh only, in both runs: by its path it runs under its
# shebang, which is /bin/sh for every command here but azure-files-sync.
set -u

TESTS=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$TESTS/.." && pwd)
export TESTS REPO

[ -d "$TESTS/cases" ] || { echo "no cases directory" >&2; exit 64; }

# What each shell is, for the summary. An sh that is bash says its version;
# any other sh, dash for one, has no version to ask, so it is named by the file
# it resolves to.
sh_version=$(sh -c 'printf %s "${BASH_VERSION:-}"')
if [ -n "$sh_version" ]; then
  SHELLS_RAN="sh (bash $sh_version)"
else
  sh_path=$(command -v sh)
  sh_real=$(readlink -f "$sh_path" 2>/dev/null) || sh_real=$sh_path
  SHELLS_RAN="sh ($sh_real)"
fi
# TODO(claude): undecided: what happens when bash is missing. The run goes on
# under sh alone and the summary says bash was not run.
if command -v bash >/dev/null 2>&1; then
  bash_version=$(bash -c 'printf %s "$BASH_VERSION"')
  with_bash=yes
  SHELLS_RAN="$SHELLS_RAN, bash --posix ($bash_version)"
else
  with_bash=no
  SHELLS_RAN="$SHELLS_RAN; bash not found, so not run under bash --posix"
fi

failed=0
ran=0

# run_case <shell label> <case file> <command...>: runs one case and prints a
# failure. Returns 1 when it failed.
run_case() {
  label=$1 case_file=$2
  shift 2
  name=$(basename "$case_file" .sh)

  # Each case gets its own shell and its own directory, so one cannot leak a
  # stubbed answer or a variable into the next.
  work=$(mktemp -d) || { echo "cannot make a working directory" >&2; exit 64; }
  out=$(WORK=$work "$@" "$case_file" 2>&1)
  status=$?
  # A case whose exit status is 0 can still have failed: most of what it calls
  # runs in a subshell, where fail's exit ends the subshell and nothing else.
  # fail leaves this behind so the failure cannot be swallowed.
  [ -f "$work/failed" ] && status=1
  rm -rf "$work"

  [ "$status" -eq 0 ] && return 0
  printf 'FAIL %s (under %s)\n' "$name" "$label"
  printf '%s\n' "$out" | sed 's/^/  /'
  return 1
}

# A case counts once, and fails if it fails under any of the shells.
# TODO(claude): undecided: whether the count is cases or case runs, one per
# shell. Cases for now, so the number means what it meant before.
for case_file in "$TESTS"/cases/*.sh; do
  [ -f "$case_file" ] || continue
  ran=$((ran + 1))
  ok=yes
  run_case sh "$case_file" sh || ok=no
  if [ "$with_bash" = yes ]; then
    run_case 'bash --posix' "$case_file" bash --posix || ok=no
  fi
  [ "$ok" = yes ] || failed=$((failed + 1))
done

[ "$ran" -eq 0 ] && { echo "no cases found" >&2; exit 64; }

printf 'tests ran under: %s\n' "$SHELLS_RAN"
if [ "$failed" -ne 0 ]; then
  printf '\ntests: %d of %d FAILED\n' "$failed" "$ran"
  exit 1
fi
printf 'tests: %d passed\n' "$ran"
exit 0
