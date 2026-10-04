#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"

describe "the review link encodes names for GitLens"

# Left raw, the + in a Claude Code worktree branch reads as a space and GitLens
# looks up a branch that does not exist. The shape is the one GitLens opened
# when tried by hand: base first, then the branch, then the repository path.
guard_path
# shellcheck source=../../home/common/lib/git-common.sh
. "$REPO/home/common/lib/git-common.sh"

actual=$(review_link "/home/stephen/.claude" main "worktree-feature+session-analysis-scripts")
expected='vscode://eamodio.gitlens/link/r/-/compare/main...worktree-feature%2Bsession-analysis-scripts?path=/home/stephen/.claude'
assert_eq "$actual" "$expected"

actual=$(review_link "/home/me/my repo" "epic/a b" "feature/x#1")
expected='vscode://eamodio.gitlens/link/r/-/compare/epic/a%20b...feature/x%231?path=/home/me/my%20repo'
assert_eq "$actual" "$expected"
