#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../mac-review-opener.sh
. "$TESTS/mac-review-opener.sh"

describe "the Mac review opener hands VS Code none of the pins"

# The opener sources the library, which pins git's settings again. A VS Code
# that code starts keeps that environment for as long as it runs, so none of
# the pins may reach it, whether VS Code was running or not.
for v in $(env | sed -n 's/^\(GIT_CONFIG_[A-Z0-9_]*\)=.*/\1/p'); do unset "$v"; done
link='vscode://eamodio.gitlens/link/r/-/compare/A...feature/x?path=/Users/me/repo'

open_review /Users/me/repo "$link" || fail "the opener failed with VS Code not running"
vscode_is_running
open_review /Users/me/repo "$link" || fail "the opener failed with VS Code running"
actual=$(cat "$CODE_ENV")

assert_eq "$actual" ''
