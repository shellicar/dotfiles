#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: a unit file that differs and is not enabled says both, and is enabled and restarted"

feature u wsl
repo_file u etc/systemd/system/off.timer '[Timer]
OnBootSec=30

[Install]
WantedBy=timers.target'
live_file /etc/systemd/system/off.timer '[Timer]
OnBootSec=30'
FAKE_UNITS="off.timer${TAB}disabled${TAB}active"

analyse

assert_eq "$(field /etc/systemd/system/off.timer state)" differs
assert_eq "$(field /etc/systemd/system/off.timer detail)" 'content differs; not enabled'
assert_eq "$(commands_of /etc/systemd/system/off.timer | tail -n 2)" 'sudo systemctl enable off.timer
sudo systemctl restart off.timer'
