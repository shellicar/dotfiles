#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: a masked unit is a link to /dev/null, with no owner or mode"

feature m wsl
mkdir -p "$SYS_REPO/system/m/etc/systemd/system" "$LIVE_ROOT/etc/systemd/system"
ln -s /dev/null "$SYS_REPO/system/m/etc/systemd/system/masked.service"
ln -s /dev/null "$SYS_REPO/system/m/etc/systemd/system/absent.service"
ln -s /dev/null "$SYS_REPO/system/m/etc/systemd/system/file.service"
ln -s /dev/null "$LIVE_ROOT/etc/systemd/system/masked.service"
live_file /etc/systemd/system/file.service '[Service]'

analyse

assert_eq "$(field /etc/systemd/system/masked.service state)" insync
assert_eq "$(field /etc/systemd/system/masked.service owner)" -
assert_eq "$(field /etc/systemd/system/masked.service role)" link

assert_eq "$(field /etc/systemd/system/absent.service state)" missing
assert_eq "$(commands_of /etc/systemd/system/absent.service)" 'sudo ln -s /dev/null /etc/systemd/system/absent.service
sudo systemctl daemon-reload'

assert_eq "$(field /etc/systemd/system/file.service state)" differs
assert_eq "$(commands_of /etc/systemd/system/file.service)" 'sudo ln -sfnT /dev/null /etc/systemd/system/file.service
sudo systemctl daemon-reload'
