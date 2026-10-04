#!/usr/bin/env bash
# Tests for home/common/lib/azure-files-sync.sh: how a resync treats files whose
# content differs on the two sides, and keep-local / keep-remote. Each case
# calls the library's functions with two local folders standing in for a local
# folder and its Azure Files share, and runs the machine's real rclone (and
# real bisync) against them.
#
# Needs rclone and git on PATH. A missing rclone is an error, exit 64, never a
# skip. Run it after changing azure-files-sync or its library; ./test.sh does
# not run it.
#
# It touches only the folder it makes with mktemp: bisync's working folder and
# rclone's config file both point inside it, and it is removed at the end.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

command -v rclone >/dev/null 2>&1 || { echo "rclone is not installed; these tests need it" >&2; exit 64; }
command -v git >/dev/null 2>&1 || { echo "git is not installed; these tests need it" >&2; exit 64; }

ROOT=$(mktemp -d) || { echo "cannot make a working directory" >&2; exit 64; }
trap 'rm -rf "$ROOT"' EXIT
export RCLONE_CONFIG="$ROOT/rclone.conf"
: > "$RCLONE_CONFIG"

# shellcheck source=../../home/common/lib/azure-files-sync.sh
. "$REPO/home/common/lib/azure-files-sync.sh"
default_filters

HOST=$(hostname)

fail() { echo "  $*"; FAILED=1; }
expect_content() { # <file> <expected content>
  if [ ! -f "$1" ]; then fail "$1 does not exist"
  elif [ "$(cat "$1")" != "$2" ]; then fail "$1 holds '$(cat "$1")', expected '$2'"
  fi
}
expect_output() { # <output> <text it must contain>
  case "$1" in *"$2"*) ;; *) fail "output lacks: $2"; printf '%s\n' "$1" | sed 's/^/    | /' ;; esac
}
# Sets L (local) and R (stand-in for Azure) to two fresh folders, and WORKDIR.
fresh() {
  CASE="$ROOT/$1"
  L="$CASE/local" R="$CASE/azure" WORKDIR="$CASE/bisync"
  mkdir -p "$L" "$R" "$WORKDIR"
}
# Same modified time on both sides, so only the content can tell them apart.
same_time() { touch -t 202601010000 "$@"; }

# ── resync conflicts ────────────────────────────────────────────────────────

a_differing_text_file_is_left_alone_and_listed() {
  fresh text
  printf 'local\n' > "$L/notes.txt"
  printf 'azure\n' > "$R/notes.txt"
  # Azure's copy is newer, which is the copy a plain resync would overwrite.
  touch -t 202601010000 "$L/notes.txt"
  touch -t 202602020000 "$R/notes.txt"
  printf 'only here\n' > "$L/other.txt"
  out=$(sync_folder "$L" "$R" 1 1 0 2>&1)
  expect_content "$L/notes.txt" local
  expect_content "$R/notes.txt" azure
  expect_content "$R/other.txt" 'only here'
  expect_output "$out" "azure-files-sync diff $L/notes.txt"
  expect_output "$out" "azure-files-sync keep-local $L/notes.txt"
  expect_output "$out" "azure-files-sync keep-remote $L/notes.txt"
  expect_output "$out" "local: 6 bytes, modified 2026-01-01 00:00:00"
}

a_differing_binary_file_keeps_both_versions() {
  fresh binary
  printf 'LOCAL\000\001' > "$L/photo.jpg"
  printf 'AZURE\000\002' > "$R/photo.jpg"
  out=$(sync_folder "$L" "$R" 1 1 0 2>&1)
  local side
  for side in "$L" "$R"; do
    if ! cmp -s "$side/photo.jpg" <(printf 'AZURE\000\002'); then fail "$side/photo.jpg is not Azure's version"; fi
    if ! cmp -s "$side/photo-$HOST.jpg" <(printf 'LOCAL\000\001'); then fail "$side/photo-$HOST.jpg is not the local version"; fi
  done
  expect_output "$out" "photo.jpg → photo-$HOST.jpg"
}

an_md5_identical_file_is_not_a_conflict() {
  fresh identical
  printf 'same\n' > "$L/same.txt"
  printf 'same\n' > "$R/same.txt"
  touch -t 202601010000 "$L/same.txt"
  touch -t 202602020000 "$R/same.txt"
  differ=$(differing_files "$L" "$R")
  [ -z "$differ" ] || fail "listed as differing: $differ"
  out=$(sync_folder "$L" "$R" 1 1 0 2>&1)
  case "$out" in *differs*) fail "treated as a conflict: $out" ;; esac
  expect_content "$L/same.txt" same
  expect_content "$R/same.txt" same
  [ ! -e "$L/same-$HOST.txt" ] || fail "renamed although identical"
}

# ── keep-local / keep-remote ────────────────────────────────────────────────

keep_without_apply_writes_nothing() {
  local side
  for side in local remote; do
    fresh "dry-$side"
    printf 'local\n' > "$L/f.txt"
    printf 'azure\n' > "$R/f.txt"
    out=$(keep_side "$side" "$L/f.txt" "$R/f.txt" 0 2>&1)
    expect_content "$L/f.txt" local
    expect_content "$R/f.txt" azure
    expect_output "$out" "-local"
    expect_output "$out" "+azure"
  done
  expect_output "$(keep_side local "$L/f.txt" "$R/f.txt" 0 2>&1)" "local → Azure"
  expect_output "$(keep_side remote "$L/f.txt" "$R/f.txt" 0 2>&1)" "Azure → local"
}

keep_without_apply_says_binary_for_a_binary_file() {
  fresh dry-binary
  printf 'LOCAL\000' > "$L/f.bin"
  printf 'AZURE\000' > "$R/f.bin"
  out=$(keep_side local "$L/f.bin" "$R/f.bin" 0 2>&1)
  expect_output "$out" "binary"
  expect_output "$out" "MD5 $(md5_of "$L/f.bin")"
  expect_output "$out" "MD5 $(md5_of "$R/f.bin")"
  cmp -s "$R/f.bin" <(printf 'AZURE\000') || fail "Azure's copy changed without --apply"
}

keep_local_with_apply_copies_local_to_azure() {
  fresh keep-local
  printf 'local\n' > "$L/f.txt"
  printf 'azure\n' > "$R/f.txt"
  same_time "$L/f.txt" "$R/f.txt"
  keep_side local "$L/f.txt" "$R/f.txt" 1 >/dev/null 2>&1
  expect_content "$L/f.txt" local
  expect_content "$R/f.txt" local
}

keep_remote_with_apply_copies_azure_to_local() {
  fresh keep-remote
  printf 'local\n' > "$L/f.txt"
  printf 'azure\n' > "$R/f.txt"
  same_time "$L/f.txt" "$R/f.txt"
  keep_side remote "$L/f.txt" "$R/f.txt" 1 >/dev/null 2>&1
  expect_content "$L/f.txt" azure
  expect_content "$R/f.txt" azure
}

# A copy rclone cannot read stands in for Azure failing (sign-in, firewall,
# network): rclone exits 1, not with its "not found" codes. Under root the
# chmod has no effect and this case cannot show anything.
an_unreadable_azure_copy_stops_keep_instead_of_reading_as_missing() {
  fresh unreadable
  printf 'local\n' > "$L/f.txt"
  printf 'azure\n' > "$R/f.txt"
  chmod 000 "$R/f.txt"
  local status=0
  keep_side local "$L/f.txt" "$R/f.txt" 1 >/dev/null 2>&1 || status=$?
  chmod 644 "$R/f.txt"
  [ "$status" != 0 ] || fail "keep-local --apply succeeded although Azure's copy could not be read"
  expect_content "$R/f.txt" azure
}

a_missing_azure_copy_reads_as_absent() {
  fresh absent
  printf 'local\n' > "$L/f.txt"
  out=$(keep_side local "$L/f.txt" "$R/f.txt" 1 2>&1) || fail "keep-local --apply failed: $out"
  expect_output "$out" "+++ /dev/null"
  expect_content "$R/f.txt" local
}

# ── runner ──────────────────────────────────────────────────────────────────

ran=0 failed=0
for t in \
  a_differing_text_file_is_left_alone_and_listed \
  a_differing_binary_file_keeps_both_versions \
  an_md5_identical_file_is_not_a_conflict \
  keep_without_apply_writes_nothing \
  keep_without_apply_says_binary_for_a_binary_file \
  keep_local_with_apply_copies_local_to_azure \
  keep_remote_with_apply_copies_azure_to_local \
  an_unreadable_azure_copy_stops_keep_instead_of_reading_as_missing \
  a_missing_azure_copy_reads_as_absent
do
  ran=$((ran + 1))
  FAILED=0
  result=$("$t"; echo "status=$FAILED")
  case "$result" in
    *status=0) ;;
    *) failed=$((failed + 1)); printf 'FAIL %s\n%s\n' "$t" "${result%status=*}" ;;
  esac
done

if [ "$failed" -ne 0 ]; then
  printf '\nsync tests: %d of %d FAILED\n' "$failed" "$ran"
  exit 1
fi
printf 'sync tests: %d passed\n' "$ran"
