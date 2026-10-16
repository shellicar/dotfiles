#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "git spread: the result lines for a worktree carry the icon its plan line showed"

# A dirty worktree behind main, with --stash: the plan says it will be
# fast-forwarded after a stash, and the run does that and puts the work back.
# The icon on the plan line is read from the output itself, and the result line
# is checked against that. The check on the icon's value only confirms the plan
# line was found and is the fast-forward one.

git_says() {
  case "$*" in
    "worktree list --porcelain")
      printf 'worktree /wt/foo\nHEAD foo-tip\nbranch refs/heads/fix/foo\n' ;;
    "rev-list --count refs/remotes/origin/HEAD..refs/heads/main") echo 0 ;;
    "-C /wt/foo status --porcelain") echo " M some-file" ;;
    "-C /wt/foo symbolic-ref --quiet --short HEAD") echo fix/foo ;;
    "-C /wt/foo rev-list --count HEAD..main-tip") echo 2 ;;
    "-C /wt/foo rev-list --count main-tip..HEAD") echo 0 ;;
    "-C /wt/foo rev-parse --verify --quiet @{u}") return 1 ;;
    "-C /wt/foo config branch.fix/foo.merge") return 1 ;;
    "-C /wt/foo rev-list --merges --parents refs/remotes/origin/HEAD..HEAD") : ;;
    "rev-list --count refs/remotes/origin/HEAD..refs/heads/fix/foo") echo 0 ;;
    "-C /wt/foo stash push --quiet --include-untracked") return 0 ;;
    "-C /wt/foo --config-env=branch.fix/foo.mergeOptions=GIT_COMMON_EMPTY merge --ff-only --quiet refs/remotes/origin/HEAD") return 0 ;;
    "-C /wt/foo stash pop --quiet") return 0 ;;
    *) fail "unexpected: git $*" ;;
  esac
}

guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"
# shellcheck source=../../home/common/bin/git-spread
. "$REPO/home/common/bin/git-spread"

# run_it waits five seconds before acting, for a ctrl-c.
sleep() { :; }

MAIN=main
MAIN_REF=refs/remotes/origin/HEAD
target=main-tip
apply=1
stash=1
PLAN=''

plan=$(plan_worktrees 2>&1)
plan_worktrees >/dev/null 2>&1
result=$(run_it 2>&1)

# The plan line starts with its icon.
icon=$(printf '%s\n' "$plan" | grep ' \[fix/foo\]: will ' | cut -d' ' -f1)
assert_eq "$icon" '⏩'

actual=$(printf '%s\n' "$result" | grep -e 'fix/foo' -e '↳')
expected="  ✅ $icon fix/foo fast-forwarded
     ↳ working tree restored"
assert_eq "$actual" "$expected"
