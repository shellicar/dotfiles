#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: a sudoers file at 0644 is wrong mode, wanting 0440 from .gitattributes"

# What system/.gitattributes's **/etc/sudoers.d/* mode=0440 makes git answer.
# That the pattern matches is shown against the real git in tests/system.
feature f wsl
repo_file f etc/sudoers.d/tester 'tester ALL=(ALL) ALL'
live_file /etc/sudoers.d/tester 'tester ALL=(ALL) ALL' 0644
FAKE_ATTRS="system/f/etc/sudoers.d/tester${TAB}mode${TAB}0440"

analyse

assert_eq "$(field /etc/sudoers.d/tester state)" owner
assert_eq "$(field /etc/sudoers.d/tester detail)" 'mode 0644, want 0440'
assert_eq "$(commands_of /etc/sudoers.d/tester)" 'sudo chmod 0440 /etc/sudoers.d/tester'
