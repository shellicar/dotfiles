. /case/lib.sh
NAME=the-planned-mask-refuses-a-folder-at-its-path

# A masked unit in the repo, and a real folder where its link belongs. The
# command the plan gives for it is run for real, as root, without sudo: it
# has to fail and leave the folder as it was, not put the link inside it.
feature m
mkdir -p "$R/system/m/etc/systemd/system"
ln -s /dev/null "$R/system/m/etc/systemd/system/masked.service"
repo_done
mkdir -p /etc/systemd/system/masked.service
printf 'keep\n' > /etc/systemd/system/masked.service/inside

plan || fail "system.sh --plan exited $status"
cmd=$(grep -F 'ln -s' /work/out | sed 's/^ *sudo //')
[ -n "$cmd" ] || fail "the plan gives no ln command for the folder"
ok "the plan gives: $cmd"

before=$(ls -A /etc/systemd/system/masked.service)
sh -c "$cmd" > /work/ln-out 2>&1
st=$?
sed 's/^/  | /' /work/ln-out
[ "$st" -ne 0 ] || fail "the planned command succeeded on a folder"
ok "the planned command refuses the folder (exit $st)"
[ -d /etc/systemd/system/masked.service ] && [ ! -L /etc/systemd/system/masked.service ] ||
  fail "the folder was replaced"
[ "$(ls -A /etc/systemd/system/masked.service)" = "$before" ] ||
  fail "the folder changed: $(ls -A /etc/systemd/system/masked.service)"
ok 'the folder is left as it was'

printf 'PASS %s\n' "$NAME"
