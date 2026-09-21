#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a branch is yours only when every commit main lacks is authored as you"

# Commits already in main belong to nobody here: C is someone else's and is on
# every branch, and it must not make any of them foreign.
#
#   main     A - B - C
#   mine          \ M1 - M2
#   theirs        \ T1 - T2
#   mixed         \ T3 - M3
commit A
commit B A
commit C B
author C them@example.com
commit M1 B
commit M2 M1
commit T1 B
commit T2 T1
author T1 them@example.com
author T2 them@example.com
commit T3 B
commit M3 T3
author T3 old-me@example.com

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/mine M2
ref_set refs/heads/theirs T2
ref_set refs/heads/mixed M3

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
MAIN_REF=refs/remotes/origin/HEAD

assert_eq "[$(branch_foreign_authors mine "$ME")]" "[]"
assert_eq "$(branch_foreign_authors theirs "$ME")" "2 of 2 by them@example.com"
# An address you used to have is not you; the row naming it is how you find it.
assert_eq "$(branch_foreign_authors mixed "$ME")" "1 of 2 by old-me@example.com"
# A repository with no identity has nobody to match, so nothing is yours.
assert_eq "$(branch_foreign_authors mine '')" "2 of 2 by me@example.com"
