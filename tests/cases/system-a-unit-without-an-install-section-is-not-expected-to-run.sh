#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: a unit with no [Install] section, which another unit starts, is in sync when its file is"

UNIT='[Service]
Type=oneshot
ExecStart=/usr/local/sbin/claude-watchdog.sh'

feature u wsl
repo_file u etc/systemd/system/claude-watchdog.service "$UNIT"
live_file /etc/systemd/system/claude-watchdog.service "$UNIT"
# FAKE_UNITS is empty, so asking systemctl about it fails the case.

analyse

assert_eq "$(field /etc/systemd/system/claude-watchdog.service state)" insync

# Its file changed: installed and reloaded, never enabled or started.
live_file /etc/systemd/system/claude-watchdog.service '[Service]'
analyse
assert_eq "$(commands_of /etc/systemd/system/claude-watchdog.service)" \
  "sudo install -o root -g root -m 0644 $SYS_REPO/system/u/etc/systemd/system/claude-watchdog.service /etc/systemd/system/claude-watchdog.service
sudo systemctl daemon-reload"
