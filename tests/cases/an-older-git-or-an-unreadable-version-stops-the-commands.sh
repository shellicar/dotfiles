#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "sourcing the library stops on a git older than 2.38, or a version it cannot read"

# The library checks `git --version` when it is sourced, so every command stops
# before doing anything else. Each answer is tried in its own shell, because a
# refusal exits.

git_says() { fail "nothing but the version should be asked: git $*"; }
guard_path

# Prints the exit status, then what was said on stderr.
source_with() (
  FAKE_GIT_VERSION=$1
  # shellcheck source=../../home/common/lib/git-common.sh
  ( . "$REPO/home/common/lib/git-common.sh" ) 2> "$WORK/err"
  printf '%s|%s' "$?" "$(cat "$WORK/err")"
)

assert_eq "$(source_with 'git version 2.55.0')" "0|"
assert_eq "$(source_with 'git version 2.38.0')" "0|"
assert_eq "$(source_with 'git version 3.0.0')" "0|"
assert_eq "$(source_with 'git version 2.39.5 (Apple Git-154)')" "0|"
assert_eq "$(source_with 'git version 2.45.0.rc1')" "0|"
assert_eq "$(source_with 'git version 2.34.1')" "1|test: needs git 2.38 or newer, found 2.34.1"
assert_eq "$(source_with 'git version 1.9.0')" "1|test: needs git 2.38 or newer, found 1.9.0"
assert_eq "$(source_with 'git 2.55.0')" \
  "1|test: cannot read the git version from 'git --version', which printed: git 2.55.0"
assert_eq "$(source_with 'git version two.forty')" \
  "1|test: cannot read the git version from 'git --version', which printed: git version two.forty"
assert_eq "$(source_with 'git version 2')" \
  "1|test: cannot read the git version from 'git --version', which printed: git version 2"
