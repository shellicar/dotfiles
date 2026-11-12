#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: a unit file that is missing or differs is installed, reloaded, and enabled or restarted"

UNIT='[Timer]
OnBootSec=30

[Install]
WantedBy=timers.target'

feature u wsl
repo_file u etc/systemd/system/new.timer "$UNIT"
repo_file u etc/systemd/system/old.timer "$UNIT"
live_file /etc/systemd/system/old.timer '[Timer]
OnBootSec=10

[Install]
WantedBy=timers.target'
mkdir -p "$LIVE_ROOT/etc/systemd/system"
# Only old.timer is asked about: a missing unit is not loaded to ask about.
FAKE_UNITS="old.timer${TAB}enabled${TAB}active"

analyse

assert_eq "$(field /etc/systemd/system/new.timer state)" missing
assert_eq "$(commands_of /etc/systemd/system/new.timer)" \
  "sudo install -o root -g root -m 0644 $SYS_REPO/system/u/etc/systemd/system/new.timer /etc/systemd/system/new.timer
sudo systemctl daemon-reload
sudo systemctl enable --now new.timer"

assert_eq "$(field /etc/systemd/system/old.timer state)" differs
assert_eq "$(commands_of /etc/systemd/system/old.timer)" \
  "sudo install -o root -g root -m 0644 $SYS_REPO/system/u/etc/systemd/system/old.timer /etc/systemd/system/old.timer
sudo systemctl daemon-reload
sudo systemctl restart old.timer"
