#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: a file in sync but with the wrong owner or mode gets just chown or chmod"

feature f wsl
repo_file f etc/a.conf 'a'
repo_file f etc/b.conf 'b'
repo_file f etc/c.conf 'c'
live_file /etc/a.conf 'a' 0600
live_file /etc/b.conf 'b' 0644
live_file /etc/c.conf 'c' 0664
FAKE_OWNERS="/etc/b.conf${TAB}tester:tester
/etc/c.conf${TAB}tester:root"

analyse

assert_eq "$(field /etc/a.conf state)" owner
assert_eq "$(field /etc/a.conf detail)" 'mode 0600, want 0644'
assert_eq "$(commands_of /etc/a.conf)" 'sudo chmod 0644 /etc/a.conf'

assert_eq "$(field /etc/b.conf state)" owner
assert_eq "$(field /etc/b.conf detail)" 'owner tester:tester, want root:root'
assert_eq "$(commands_of /etc/b.conf)" 'sudo chown root:root /etc/b.conf'

assert_eq "$(field /etc/c.conf detail)" 'owner tester:root, want root:root, mode 0664, want 0644'
assert_eq "$(commands_of /etc/c.conf)" 'sudo chown root:root /etc/c.conf
sudo chmod 0644 /etc/c.conf'
assert_eq "$(diff_of /etc/c.conf)" '@@ -1,2 +1,2 @@
-owner tester:root
-mode 0664
+owner root:root
+mode 0644'
