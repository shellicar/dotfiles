#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: a file the machine lacks is missing, installed after the folders above it"

feature tmp wsl
repo_file tmp etc/tmpfiles.d/tmp.conf 'd /tmp 1777 root root 30d'
mkdir -p "$LIVE_ROOT/etc"

analyse

assert_eq "$(field /etc/tmpfiles.d/tmp.conf state)" missing
assert_eq "$(field /etc/tmpfiles.d/tmp.conf detail)" missing
assert_eq "$(commands_of /etc/tmpfiles.d/tmp.conf)" "sudo install -d -o root -g root -m 0755 /etc/tmpfiles.d
sudo install -o root -g root -m 0644 $SYS_REPO/system/tmp/etc/tmpfiles.d/tmp.conf /etc/tmpfiles.d/tmp.conf"
assert_contains "$(diff_of /etc/tmpfiles.d/tmp.conf)" '+d /tmp 1777 root root 30d'
