#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: a unit with an [Install] section that is not enabled or not running is not in effect"

UNIT='[Timer]
OnBootSec=30

[Install]
WantedBy=timers.target'

feature u wsl
for t in off stopped both fine; do
  repo_file u "etc/systemd/system/$t.timer" "$UNIT"
  live_file "/etc/systemd/system/$t.timer" "$UNIT"
done
FAKE_UNITS="off.timer${TAB}disabled${TAB}active
stopped.timer${TAB}enabled${TAB}inactive
both.timer${TAB}disabled${TAB}inactive
fine.timer${TAB}enabled${TAB}active"

analyse

assert_eq "$(field /etc/systemd/system/off.timer state)" inactive
assert_eq "$(field /etc/systemd/system/off.timer detail)" 'not enabled'
assert_eq "$(field /etc/systemd/system/off.timer label)" off.timer
assert_eq "$(commands_of /etc/systemd/system/off.timer)" 'sudo systemctl enable off.timer'
assert_eq "$(diff_of /etc/systemd/system/off.timer)" '@@ -1,2 +1,2 @@
-is-enabled disabled
+is-enabled enabled
 is-active active'

assert_eq "$(field /etc/systemd/system/stopped.timer state)" inactive
assert_eq "$(field /etc/systemd/system/stopped.timer detail)" 'not running'
assert_eq "$(commands_of /etc/systemd/system/stopped.timer)" 'sudo systemctl start stopped.timer'

assert_eq "$(field /etc/systemd/system/both.timer detail)" 'not enabled, not running'
assert_eq "$(commands_of /etc/systemd/system/both.timer)" 'sudo systemctl enable --now both.timer'

assert_eq "$(field /etc/systemd/system/fine.timer state)" insync
assert_eq "$(field /etc/systemd/system/fine.timer commands)" -
