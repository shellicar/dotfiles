#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: a file whose content differs shows git's diff from the machine to the repo"

feature hang wsl
repo_file hang usr/local/sbin/watchdog.sh 'GRACE=60' executable
live_file /usr/local/sbin/watchdog.sh 'GRACE=30' 0755

analyse

assert_eq "$(field /usr/local/sbin/watchdog.sh state)" differs
assert_eq "$(field /usr/local/sbin/watchdog.sh detail)" 'content differs'
assert_eq "$(commands_of /usr/local/sbin/watchdog.sh)" \
  "sudo install -o root -g root -m 0755 $SYS_REPO/system/hang/usr/local/sbin/watchdog.sh /usr/local/sbin/watchdog.sh"
assert_eq "$(diff_of /usr/local/sbin/watchdog.sh)" '@@ -1 +1 @@
-GRACE=30
+GRACE=60'
