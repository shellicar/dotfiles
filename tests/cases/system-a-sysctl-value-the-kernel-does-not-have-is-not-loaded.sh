#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh: a sysctl file in sync whose values the kernel does not have is not loaded"

feature hang wsl
repo_file hang etc/sysctl.d/90-hung.conf '# a comment

kernel.hung_task_timeout_secs = 120
-kernel.panic_on_oops=0'
live_file /etc/sysctl.d/90-hung.conf '# a comment

kernel.hung_task_timeout_secs = 120
-kernel.panic_on_oops=0'
repo_file hang etc/sysctl.d/91-loaded.conf 'net.ipv4.tcp_rmem = 4096	87380   6291456'
live_file /etc/sysctl.d/91-loaded.conf 'net.ipv4.tcp_rmem = 4096	87380   6291456'
FAKE_SYSCTL='kernel.hung_task_timeout_secs=0
kernel.panic_on_oops=0
net.ipv4.tcp_rmem=4096	87380	6291456'

analyse

assert_eq "$(field /etc/sysctl.d/90-hung.conf state)" inactive
assert_eq "$(field /etc/sysctl.d/90-hung.conf detail)" 'not loaded'
assert_eq "$(commands_of /etc/sysctl.d/90-hung.conf)" 'sudo sysctl -p /etc/sysctl.d/90-hung.conf'
assert_eq "$(diff_of /etc/sysctl.d/90-hung.conf)" '@@ -1,2 +1,2 @@
-kernel.hung_task_timeout_secs = 0
+kernel.hung_task_timeout_secs = 120
 kernel.panic_on_oops = 0'

# Blanks inside a value are compared as one space, as sysctl prints tabs.
assert_eq "$(field /etc/sysctl.d/91-loaded.conf state)" insync
