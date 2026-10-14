#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-git.sh
. "$TESTS/fake-git.sh"

describe "a merged branch whose remote still exists says to check the PR"

# The content is in main, yet the remote branch was not deleted the way a
# merged pull request deletes it.
#
#   main   A - B - C
#   topic        \ T1    content landed in main as C
commit A
commit B A
commit C B
commit T1 B
lands T1

ref_set refs/heads/main C
ref_set refs/remotes/origin/HEAD C
ref_set refs/heads/topic T1
ref_set refs/remotes/origin/topic T1

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

branch_beyond_cap() { return 1; }

# topic tracks origin/topic.
git_config_says() {
  case "$1" in
    branch.topic.*) return 0 ;;
    *) return 1 ;;
  esac
}

v=$(branch_verdict topic)
IFS="$TAB" read -r class n _ gone _ <<EOF
$v
EOF
branch_reason topic "$class" "$n" "$gone"

# The sentence carries an em dash, written here as its UTF-8 bytes.
dash=$(printf '\342\200\224')
assert_eq "$class $REASON" "merged merged, but remote not gone $dash check the PR"
