#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "--depth bounds how far back the content walk looks"

# The walk is tip-first and stops after WALK_DEPTH commits. A branch whose join
# point sits deeper than that is reported as not found rather than merged, which
# is the safe answer: --depth buys certainty about older branches, and the
# default is what keeps an ordinary run quick.

git_says() {
  case "$*" in
    "merge-base refs/heads/deep refs/remotes/origin/HEAD") echo fork-point ;;
    "merge-base --is-ancestor refs/heads/deep refs/remotes/origin/HEAD") return 1 ;;
    "rev-list --count refs/remotes/origin/HEAD ^refs/heads/deep") echo 5 ;;
    "rev-list -n "*" fork-point..refs/heads/deep")
      printf '%s\n' c5 c4 c3 c2 c1 | head -n "$WALK_DEPTH" ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

# The content of the walk is not the subject here, so it is stubbed at the seam
# rather than through git diff and shasum: each commit hashes to its own name.
content_hash_cached() { printf 'content-of-%s\n' "$2"; }

MAIN_IDX=$WORK/idx
# Only the fourth commit back matches something in main.
printf 'content-of-c2\n' > "$MAIN_IDX"

WALK_DEPTH=2
shallow=$(commits_not_in_main refs/heads/deep)
WALK_DEPTH=5
deep=$(commits_not_in_main refs/heads/deep)

expected="shallow=-1 deep=3"
actual="shallow=$shallow deep=$deep"
assert_eq "$actual" "$expected"
