#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../mac-review-opener.sh
. "$TESTS/mac-review-opener.sh"

describe "the Mac review opener refuses a call without a folder and a link"

vscode_is_running

for args in "" "/Users/me/repo" "/Users/me/repo vscode://a vscode://b"; do
  # shellcheck disable=SC2086 # the arguments, split on purpose
  err=$(open_review $args 2>&1 >/dev/null)
  status=$?
  assert_eq "$status" 64
  assert_eq "$err" "usage: vscode-open-review <folder> <link>"
done

actual=$(cat "$CODE_LOG")
assert_eq "$actual" ''
