#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "branch_verdict names the class of every branch shape"

# This is the function that decides what gets deleted, and all seven classes it
# can return are asserted here, so a change that moves a branch from one to
# another has to move a line in this file to do it.
#
#   main         A - B - C
#   empty            B              nothing of its own
#   merged             \ M1         its work landed in main as C
#   review             \ R1 - R2    R1 landed, then one more on top
#   unmerged           \ U1         own work, nowhere in main
#   suspect            \ S1         same, but its remote is gone
#   ancient            \ P1         too far behind to be worth walking
#   deep               \ D1 - ... - D6   more commits than WALK_DEPTH, and
#                                        none of the five tested landed
commit A
commit B A
commit C B
commit M1 B
commit R1 B
commit R2 R1
commit U1 B
commit S1 B
commit P1 B
commit D1 B
commit D2 D1
commit D3 D2
commit D4 D3
commit D5 D4
commit D6 D5
lands M1
lands R1

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/empty B
ref_set refs/heads/merged M1
ref_set refs/heads/review R2
ref_set refs/heads/unmerged U1
ref_set refs/heads/suspect S1
ref_set refs/heads/ancient P1
ref_set refs/heads/deep D6
# unmerged still has its remote branch; suspect's was deleted, which is what
# separates "gone, and the content is nowhere" from "local-only work".
ref_set refs/remotes/origin/unmerged U1

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

# Both track origin; only unmerged's remote ref still exists, above.
git_config_says() {
  case "$1" in
    branch.suspect.*|branch.unmerged.*) return 0 ;;
    *) return 1 ;;
  esac
}

# ancient is past the cap; nothing else is.
branch_beyond_cap() { [ "$1" = refs/heads/ancient ]; }

WT_MAP=''
WALK_DEPTH=5

class_of() {
  v=$(branch_verdict "$1")
  IFS="$TAB" read -r class _ <<EOF
$v
EOF
  printf '%s' "$class"
}

expected="empty merged review unmerged suspect inconclusive unchecked"
actual="$(class_of empty) $(class_of merged) $(class_of review) $(class_of unmerged) $(class_of suspect) $(class_of ancient) $(class_of deep)"
assert_eq "$actual" "$expected"
