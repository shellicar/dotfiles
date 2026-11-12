#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh --plan: the temporary files it diffs from are gone when it finishes"

# Being interrupted is covered in tests/system, against the real command.
feature f wsl
repo_file f etc/a.conf 'a'
live_file /etc/a.conf 'b'

out=$(system_plan_main)
assert_contains "$out" 'content differs'
assert_eq "$(ls -A "$TMPDIR")" ''
