#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: /etc/wsl.conf in sync but changed since boot needs a restart, printed above the rows"

feature boot wsl
repo_file boot etc/wsl.conf '[boot]
systemd=true'
live_file /etc/wsl.conf '[boot]
systemd=true'

FAKE_BOOT=1000 FAKE_MTIME=2000
analyse
assert_eq "$(field /etc/wsl.conf state)" restart
assert_eq "$(field /etc/wsl.conf commands)" -
out=$(system_print_plan)
assert_contains "$out" 'Needs a restart
  ⚠️ /etc/wsl.conf  [boot]  in sync, not in effect until WSL restarts: wsl --shutdown'
assert_contains "$out" '0 out of line'

FAKE_BOOT=3000 FAKE_MTIME=2000
analyse
assert_eq "$(field /etc/wsl.conf state)" insync

# A mode fix alone needs no restart.
chmod 0600 "$LIVE_ROOT/etc/wsl.conf"
analyse
assert_eq "$(field /etc/wsl.conf state)" owner
assert_eq "$(field /etc/wsl.conf restart)" -

# A change to it is a row, with the restart said beside its commands.
live_file /etc/wsl.conf '[boot]'
analyse
assert_eq "$(field /etc/wsl.conf state)" differs
assert_contains "$(system_preview "$(row_of /etc/wsl.conf)" '')" \
  'then restart for it to take effect: wsl --shutdown (not run)'
