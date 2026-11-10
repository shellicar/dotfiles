#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: when systemctl cannot reach systemd, a unit is unavailable, never read as not enabled"

UNIT='[Timer]
OnBootSec=30

[Install]
WantedBy=timers.target'

feature u wsl
repo_file u etc/systemd/system/a.timer "$UNIT"
live_file /etc/systemd/system/a.timer "$UNIT"
FAKE_BUS=down

analyse

assert_eq "$(field /etc/systemd/system/a.timer state)" unknown
assert_eq "$(field /etc/systemd/system/a.timer detail)" \
  'cannot tell if enabled or running: Failed to connect to bus: Operation not permitted'
assert_eq "$(field /etc/systemd/system/a.timer commands)" -
assert_contains "$(system_row_line unknown a.timer x 7)" '[-]'
