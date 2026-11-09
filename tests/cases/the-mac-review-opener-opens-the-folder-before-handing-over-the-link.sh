#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../mac-review-opener.sh
. "$TESTS/mac-review-opener.sh"

describe "the Mac review opener opens the folder before handing over the link"

# VS Code is running, and hands a link to the window it opened or focused last,
# so the folder reaches it first. The link goes on as it came: git review has
# already encoded it for GitLens.
folder='/Users/me/my repo'
link='vscode://eamodio.gitlens/link/r/-/compare/A...feature/x%2B1?path=/Users/me/my%20repo'
expected="[$folder]
[--open-url][$link]"
vscode_is_running

open_review "$folder" "$link" || fail "the opener failed"
actual=$(cat "$CODE_LOG")

assert_eq "$actual" "$expected"
