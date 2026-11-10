. /case/lib.sh
NAME=each-state-is-read-from-real-files-by-an-ordinary-user

feature f
repo_file f etc/insync.conf 'same'
repo_file f etc/missing.conf 'new'
repo_file f etc/differs.conf 'wanted'
repo_file f etc/owned.conf 'owned'
repo_file f etc/sudoers.d/tester 'tester ALL=(ALL) ALL'
repo_file f etc/sudoers.d/locked 'locked ALL=(ALL) ALL'
repo_file f usr/local/sbin/tool 'echo tool' executable
repo_file f etc/user.conf 'User={{user}}'
repo_file f etc/sysctl.d/90-ostype.conf 'kernel.ostype = Linux'
repo_file f etc/sysctl.d/91-ostype.conf 'kernel.ostype = Plan9'
repo_done

live_file /etc/insync.conf 'same' root:root 0644
live_file /etc/differs.conf 'had' root:root 0644
live_file /etc/owned.conf 'owned' tester:tester 0644
live_file /etc/sudoers.d/tester 'tester ALL=(ALL) ALL' root:root 0644
live_file /etc/sudoers.d/locked 'locked ALL=(ALL) ALL' root:root 0440
live_file /usr/local/sbin/tool 'echo tool' root:root 0755
live_file /etc/user.conf 'User=tester' root:root 0644
live_file /etc/sysctl.d/90-ostype.conf 'kernel.ostype = Linux' root:root 0644
live_file /etc/sysctl.d/91-ostype.conf 'kernel.ostype = Plan9' root:root 0644

TARGETS='/etc/insync.conf /etc/missing.conf /etc/differs.conf /etc/owned.conf
/etc/sudoers.d/tester /etc/sudoers.d/locked /usr/local/sbin/tool /etc/user.conf
/etc/sysctl.d/90-ostype.conf /etc/sysctl.d/91-ostype.conf'
# shellcheck disable=SC2086
before=$(fingerprint $TARGETS)

plan || fail "system.sh --plan exited $status"

# The row for a path: its icon, then the path, then what is out of line.
row() { # <icon> <path> <detail> <what>
  line=$(grep -F " $1 $2 " /work/out) || fail "$4: no row for $2"
  case $line in
    *"  $3") ok "$4" ;;
    *) fail "$4: expected the row to end with '$3': $line" ;;
  esac
}

has '✓ /etc/insync.conf  [f]' 'a root-owned file in sync is in sync'
has '✓ /usr/local/sbin/tool  [f]' 'an executable file at 0755 is in sync'
has '✓ /etc/user.conf  [f]' '{{user}} is the user running it'
has '✓ /etc/sysctl.d/90-ostype.conf  [f]' 'a sysctl value the kernel has is in sync'
row '🆕' /etc/missing.conf 'missing' 'a file the machine lacks is missing'
row '✏️' /etc/differs.conf 'content differs' 'a file with other content differs'
row '🔐' /etc/owned.conf 'owner tester:tester, want root:root' "a file owned by tester is the wrong owner"
row '🔐' /etc/sudoers.d/tester 'mode 0644, want 0440' 'a sudoers file at 0644 wants 0440'
has '/etc/sudoers.d/tester  root:root 0440' "the sudoers file's mode comes from system/.gitattributes"
row '❔' /etc/sudoers.d/locked 'cannot be read without root' 'a file only root can read is unavailable'
row '💤' /etc/sysctl.d/91-ostype.conf 'not loaded' 'a sysctl value the kernel lacks is not loaded'

# shellcheck disable=SC2086
after=$(fingerprint $TARGETS)
[ "$before" = "$after" ] || fail "the targets changed:
$before
---
$after"
ok 'no target changed'
[ -e /work/sudo-called ] && fail "sudo was called: $(cat /work/sudo-called)"
ok 'nothing asked for root'
[ -z "$(ls -A /work/tmp)" ] || fail "left behind: $(ls -A /work/tmp)"
ok 'nothing left in TMPDIR'

printf 'PASS %s\n' "$NAME"
