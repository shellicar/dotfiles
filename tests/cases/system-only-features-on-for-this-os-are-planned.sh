#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: a feature whose platforms file does not name the OS is left out"

feature both macos wsl
repo_file both etc/both.conf 'b'
feature mac macos
repo_file mac etc/mac.conf 'm'
# A feature with no platforms file is on for nothing.
mkdir -p "$SYS_REPO/system/none/etc"
printf 'n\n' > "$SYS_REPO/system/none/etc/none.conf"
OS=wsl

analyse

assert_eq "$FEATURES_ON" "both
"
assert_eq "$(printf '%s' "$ROWS" | cut -f2)" /etc/both.conf
# The platforms file is not an item.
assert_not_contains "$ROWS" platforms

out=$(system_plan_main)
assert_contains "$out" 'wsl · 1 features · 1 items'
assert_contains "$out" 'reading features ... 1 of 3 on for wsl'
