#!/bin/sh
set -u
TESTS=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(cd "$TESTS/.." && pwd)
# shellcheck source=../harness.sh
. "$TESTS/harness.sh"
# shellcheck source=../fake-system.sh
. "$TESTS/fake-system.sh"

describe "system.sh --plan: in-sync items above, then each row under its feature with its preview beneath it"

feature hang wsl
repo_file hang etc/sysctl.d/90-hung.conf 'kernel.hung_task_timeout_secs = 120'
live_file /etc/sysctl.d/90-hung.conf 'kernel.hung_task_timeout_secs = 120'
repo_file hang usr/local/sbin/w.sh 'GRACE=60' executable
live_file /usr/local/sbin/w.sh 'GRACE=30' 0755
feature tmp wsl
repo_file tmp etc/tmpfiles.d/tmp.conf 'd /tmp 1777 root root 30d'
live_file /etc/tmpfiles.d/tmp.conf 'd /tmp 1777 root root 30d' 0600
FAKE_SYSCTL='kernel.hung_task_timeout_secs=120'

out=$(system_plan_main)

assert_eq "$out" "system.sh
wsl · 2 features · 3 items
  reading features ... 2 of 2 on for wsl
  comparing with the machine ... 2 out of line

In sync
  ✓ /etc/sysctl.d/90-hung.conf  [hang]

wsl  [x] runs, [ ] does not, [-] unavailable
hang
   [x] ✏️ /usr/local/sbin/w.sh      content differs
       /usr/local/sbin/w.sh  root:root 0755
       @@ -1 +1 @@
       -GRACE=30
       +GRACE=60
       will run:
         sudo install -o root -g root -m 0755 $SYS_REPO/system/hang/usr/local/sbin/w.sh /usr/local/sbin/w.sh
tmp
   [x] 🔐 /etc/tmpfiles.d/tmp.conf  mode 0600, want 0644
       /etc/tmpfiles.d/tmp.conf  root:root 0644
       @@ -1,2 +1,2 @@
        owner root:root
       -mode 0600
       +mode 0644
       will run:
         sudo chmod 0644 /etc/tmpfiles.d/tmp.conf

plan only, nothing was touched"
