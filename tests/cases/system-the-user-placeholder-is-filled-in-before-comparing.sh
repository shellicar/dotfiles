#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: {{user}} is the running user's name, in the comparison and in the install"

feature u wsl
repo_file u etc/systemd/system/w.service '[Service]
User={{user}}'
live_file /etc/systemd/system/w.service '[Service]
User=tester'
SYS_USER=tester

analyse
assert_eq "$(field /etc/systemd/system/w.service state)" insync

SYS_USER=someone
analyse
assert_eq "$(field /etc/systemd/system/w.service state)" differs
assert_eq "$(diff_of /etc/systemd/system/w.service)" '@@ -1,2 +1,2 @@
 [Service]
-User=tester
+User=someone'
assert_contains "$(commands_of /etc/systemd/system/w.service)" \
  "sed 's/{{user}}/someone/g' $SYS_REPO/system/u/etc/systemd/system/w.service | sudo install -o root -g root -m 0644 /dev/stdin /etc/systemd/system/w.service"
