#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../mac-review-opener.sh
. "$TESTS/mac-review-opener.sh"

describe "the Mac review opener starts VS Code with the folder and the link together"

# VS Code is not running. One launch carries both, so the link cannot reach
# VS Code before the folder's window exists. --open-url takes every plain
# argument as a link, so the folder goes as a file URI.
folder='/Users/me/my repo'
link='vscode://eamodio.gitlens/link/r/-/compare/A...feature/x%2B1?path=/Users/me/my%20repo'
expected="[--folder-uri][file:///Users/me/my%20repo][--open-url][$link]"

open_review "$folder" "$link" || fail "the opener failed"
actual=$(cat "$CODE_LOG")

assert_eq "$actual" "$expected"
