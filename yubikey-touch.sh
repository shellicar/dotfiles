#!/bin/sh
# Set the OpenPGP touch policy on the inserted YubiKey.
#
# Each key slot carries its own policy, and scdaemon binds to one card at a time.
# Run it once per key, with that key in the port and the others out.
#
# It reads the current policy per slot and only writes the ones that differ, so a
# slot already at the wanted value costs nothing. ykman asks for the admin
# passphrase for each slot it writes. Three wrong attempts wipe the OpenPGP
# application, so the first failure stops the run rather than spending the rest.
#
# Reading the card takes it away from scdaemon, which was holding it exclusively.
# That clears the agent's cached passphrase as if the key had been unplugged, so
# expect the next commit to prompt.
#
# The attestation slot is left alone. It is unused here, and it is the one ykman
# singles out as unrecoverable if set to fixed.
#
# fixed and cached-fixed are refused outright: both remove the ability to change
# your mind, and undoing either means deleting the private key.
#
# Dry run by default. --apply sets it.
set -e

SLOTS="sig dec aut"
POLICY=off

apply=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)  apply=1 ;;
    --policy) shift; POLICY="${1:-}" ;;
    *)        echo "ERROR: unknown option: $1" >&2; exit 64 ;;
  esac
  shift
done

case "$POLICY" in
  off|on|cached) ;;
  fixed|cached-fixed)
    echo "ERROR: $POLICY cannot be undone without deleting the private key" >&2
    exit 64 ;;
  *)
    echo "ERROR: policy must be off, on or cached" >&2
    exit 64 ;;
esac

command -v ykman >/dev/null 2>&1 || { echo "ERROR: ykman not found" >&2; exit 64; }

LIB="$(dirname "$0")/home/common/lib/yubikeys.sh"
[ -f "$LIB" ] || { echo "ERROR: $LIB not found" >&2; exit 64; }
# shellcheck source=/dev/null
. "$LIB"

serials=$(ykman list --serials 2>/dev/null || true)
count=$(printf '%s\n' "$serials" | grep -c . || true)

if [ "$count" -eq 0 ]; then
  echo "ERROR: no YubiKey inserted" >&2
  exit 1
fi
if [ "$count" -gt 1 ]; then
  echo "ERROR: more than one YubiKey inserted; unplug all but one" >&2
  printf '%s\n' "$serials" | sed 's/^/  /' >&2
  exit 1
fi

case "$serials" in
  "$YUBIKEY_A_SERIAL") name="Key A" ;;
  "$YUBIKEY_B_SERIAL") name="Key B" ;;
  "$YUBIKEY_C_SERIAL") name="Key C" ;;
  *) echo "ERROR: $serials is not one of the three in yubikeys.sh" >&2; exit 1 ;;
esac

INFO=$(ykman openpgp info)

# The slot sections are named in full and the policy sits two lines under each,
# so the section header is what says which slot a Touch policy line belongs to.
current_policy() {
  printf '%s\n' "$INFO" | awk -v want="$1" '
    /Signature key:/      { slot = "sig" }
    /Decryption key:/     { slot = "dec" }
    /Authentication key:/ { slot = "aut" }
    /Touch policy:/       { if (slot == want) { print tolower($3); exit } }
  '
}

echo "Plan: $name ($serials)"
echo ""
printf '%s\n' "$INFO" | sed 's/^/  /'
echo ""

TODO=""
for s in $SLOTS; do
  cur=$(current_policy "$s")
  if [ -z "$cur" ]; then
    echo "ERROR: could not read the $s touch policy out of ykman openpgp info" >&2
    exit 1
  fi
  if [ "$cur" = "$POLICY" ]; then
    echo "  $s is already $POLICY"
  else
    echo "  $s is $cur, would become $POLICY"
    TODO="$TODO $s"
  fi
done
echo ""

if [ -z "$TODO" ]; then
  echo "Nothing to change."
  exit 0
fi

if [ "$apply" -eq 0 ]; then
  echo "Dry run. Re-run with --apply to set it."
  exit 0
fi

for s in $TODO; do
  ykman openpgp keys set-touch "$s" "$POLICY" --force
  echo "  $s set to $POLICY"
done

echo ""
echo "Now:"
ykman openpgp info | sed 's/^/  /'
