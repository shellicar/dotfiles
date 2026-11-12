#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: a live file it cannot read is unavailable, and nothing asks for root"

feature f wsl
repo_file f etc/sudoers.d/tester 'tester ALL=(ALL) ALL'
live_file /etc/sudoers.d/tester 'tester ALL=(ALL) ALL' 0000

# Root reads a file at 0000, so run as root this case has nothing to show.
[ -r "$LIVE_ROOT/etc/sudoers.d/tester" ] && exit 0

analyse
assert_eq "$(field /etc/sudoers.d/tester state)" unknown
assert_eq "$(field /etc/sudoers.d/tester detail)" 'cannot be read without root'
assert_eq "$(field /etc/sudoers.d/tester commands)" -
