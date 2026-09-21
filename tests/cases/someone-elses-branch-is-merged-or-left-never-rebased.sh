#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "someone else's branch is merged when it can be pushed and left alone when not, never rebased"

# Three branches cut from the same place, each of which would be rebased on its
# own merits. Only whose commits they carry, and whether a merge has somewhere
# to go, tells them apart.
#
#   main     A - B - C
#   mine          \ M1
#   pushed        \ T1        (them, tracks origin)
#   local         \ T2        (them, never pushed)
commit A
commit B A
commit C B
commit M1 B
commit T1 B
commit T2 B
author T1 them@example.com
author T2 them@example.com

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/mine M1
ref_set refs/heads/pushed T1
ref_set refs/heads/local T2

git_config_says() {
  case "$1" in branch.pushed.*) return 0 ;; esac
  return 1
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
MAIN=main
MAIN_REF=refs/remotes/origin/HEAD

assert_eq "$(owned_update_verdict . mine)" "rebase${TAB}B${TAB}-"
assert_eq "$(owned_update_verdict . pushed)" "merge${TAB}-${TAB}1 of 1 by them@example.com"
assert_eq "$(owned_update_verdict . local)" \
  "none${TAB}not yours (1 of 1 by them@example.com), and nowhere to push a merge${TAB}1 of 1 by them@example.com"
