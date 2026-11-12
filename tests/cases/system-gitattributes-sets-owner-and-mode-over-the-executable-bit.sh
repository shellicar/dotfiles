#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: owner and mode are root:root and 0755 or 0644 from git's executable bit, unless .gitattributes says"

feature f wsl
repo_file f usr/local/sbin/tool 'x' executable
repo_file f etc/plain.conf 'p'
repo_file f etc/sudoers.d/tester 'tester ALL=(ALL) ALL'
repo_file f etc/owned.conf 'o'
FAKE_ATTRS="system/f/etc/sudoers.d/tester${TAB}mode${TAB}0440
system/f/etc/owned.conf${TAB}owner${TAB}tester:adm"

analyse

assert_eq "$(field /usr/local/sbin/tool owner) $(field /usr/local/sbin/tool mode)" 'root:root 0755'
assert_eq "$(field /etc/plain.conf owner) $(field /etc/plain.conf mode)" 'root:root 0644'
assert_eq "$(field /etc/sudoers.d/tester owner) $(field /etc/sudoers.d/tester mode)" 'root:root 0440'
assert_eq "$(field /etc/owned.conf owner) $(field /etc/owned.conf mode)" 'tester:adm 0644'
assert_contains "$(commands_of /etc/owned.conf)" 'sudo install -o tester -g adm -m 0644 '
assert_contains "$(cat "$GIT_LOG")" "-C $SYS_REPO check-attr -z owner mode -- system/f/etc/owned.conf system/f/etc/plain.conf system/f/etc/sudoers.d/tester system/f/usr/local/sbin/tool"
