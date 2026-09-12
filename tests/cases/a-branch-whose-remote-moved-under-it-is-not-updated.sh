#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "a branch whose own remote has moved under it is not updated"

# The update for a branch with work of its own is a rebase, and a rebase here
# force-pushes. --force-with-lease does not make that safe: the lease compares
# against the remote-tracking ref, and this run's own fetch has just moved that
# ref onto the commit in question, so the lease agrees and the push goes
# through. The commit destroyed is whoever pushed it.
#
# Three shapes have to be told apart, because only the first is the dangerous
# one. Refusing the second would refuse the ordinary case of having committed
# and not pushed yet, and refusing the third would refuse every local branch.

git_says() {
  case "$*" in
    # The remote holds a commit this branch does not.
    "-C /wt/moved rev-parse --verify --quiet @{u}") echo remote-tip ;;
    "-C /wt/moved merge-base --is-ancestor remote-tip HEAD") return 1 ;;
    # Ahead of its remote and nothing else: ordinary unpushed work.
    "-C /wt/ahead rev-parse --verify --quiet @{u}") echo behind-tip ;;
    "-C /wt/ahead merge-base --is-ancestor behind-tip HEAD") return 0 ;;
    # Never pushed, so there is no remote to have moved.
    "-C /wt/local rev-parse --verify --quiet @{u}") return 1 ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

verdict_of() {
  if branch_diverged_from_remote "$1" "$2"; then printf 'stopped'; else printf 'updated'; fi
}

# The trunk asks git nothing: being behind origin/main is its ordinary state and
# nothing here ever force-pushes it.
expected='stopped updated updated updated'
actual="$(verdict_of /wt/moved feature/moved) $(verdict_of /wt/ahead feature/ahead) $(verdict_of /wt/local feature/local) $(verdict_of /wt/trunk main)"
assert_eq "$actual" "$expected"
