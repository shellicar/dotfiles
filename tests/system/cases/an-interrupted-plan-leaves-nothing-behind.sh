. /case/lib.sh
NAME=an-interrupted-plan-leaves-nothing-behind

feature f
repo_file f etc/sysctl.d/90-ostype.conf 'kernel.ostype = Linux'
repo_done
live_file /etc/sysctl.d/90-ostype.conf 'kernel.ostype = Linux' root:root 0644

# A sysctl that notes what is in TMPDIR, then takes long enough for the run to
# be interrupted while its temporary files exist.
mkdir -p /work/slow /work/note
chmod 1777 /work/note
printf '#!/bin/sh\nls /work/tmp > /work/note/seen\nsleep 5\n' > /work/slow/sysctl
chmod 0755 /work/slow/sysctl

for sig in INT TERM HUP; do
  rm -f /work/note/seen
  runuser -u tester -- env PATH="/work/slow:$PATH" TMPDIR=/work/tmp \
    timeout -s "$sig" 1 "$R/system.sh" --plan > /work/out 2>&1
  status=$?
  [ "$status" -eq 124 ] || { cat /work/out; fail "SIG$sig: expected the run to be cut short, it exited $status"; }
  grep -q '^system\.' /work/note/seen || fail "SIG$sig: the temporary directory did not exist while it ran"
  [ -z "$(ls -A /work/tmp)" ] || fail "SIG$sig: left behind: $(ls -A /work/tmp)"
  ok "interrupted by SIG$sig, nothing left in TMPDIR"
done

printf 'PASS %s\n' "$NAME"
