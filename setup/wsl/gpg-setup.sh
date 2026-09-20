#!/bin/sh
#
# GPG setup, WSL. Reached through ../../gpg-setup.sh, which dispatches on the raw
# OS; see that file for why WSL and native Linux are not the same case.
#
# The command surface matches the macOS implementation, but almost nothing behind
# it is shared, because the card is not local here. Windows owns the reader, and
# its gpg-agent holds the card; this distro reaches that agent through the socket
# bridge (home/wsl/bin/gpg-bridge, installed by gpg-bridge-install). So:
#
#   - There is no local gpg-agent to configure. Its cache TTL, its pinentry and
#     its scdaemon all live on the Windows side, and the packaged agent sockets
#     here are masked so the bridge can own the socket path.
#   - ykman is not used, and does not need installing. "Exactly one card" is
#     answered by asking the agent what it can see, which is the only card that
#     can be addressed from here anyway.
#   - The public key is read off the card rather than fetched, same as macOS, but
#     without gpg-card: Ubuntu does not ship it. SCD READCERT through the agent
#     returns the DER container GnuPG wraps the keyblock in, and openssl unwraps
#     it. The fingerprint is checked before the import, so a wrong card is caught
#     rather than trusted.
#
# What is deliberately not done here: writing gpg-agent.conf, touching a keychain,
# scheduling an agent kill. All three would be configuring an agent this machine
# does not run, and would look like they had worked.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)

# GPG_FINGERPRINT and the serials, so a card is checked rather than taken on trust.
LIB="$DIR/../../home/common/lib/yubikeys.sh"
[ -f "$LIB" ] || { echo "ERROR: $LIB not found" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

GPG_CONF="${GNUPGHOME:-$HOME/.gnupg}/gpg.conf"
SERVICE=gpg-bridge.service
CERT_SLOT=3

usage() {
  echo "Usage: $(basename "$0") <command>"
  echo ""
  echo "Commands:"
  echo "  --test-sign    Test signing with the key on the card, through the bridge"
  echo "  --test-sign --hardware"
  echo "                 The same thing. The card is the only key reachable here"
  echo "  --configure    Configure this distro to sign with the card"
  echo "  --configure --hardware"
  echo "                 The same thing. There is no on-disk key mode under WSL"
  echo "  --reset        Restart the bridge (next sign re-reaches the agent)"
  echo "  --schedule     Not applicable under WSL; explains why"
  exit 1
}

# The bridge, not a card reader, is what can be missing here, and the difference
# matters: a stopped bridge and an absent key look identical to gpg otherwise.
require_bridge() {
  if [ "$(systemctl --user is-active "$SERVICE" 2>/dev/null || true)" != active ]; then
    echo "ERROR: $SERVICE is not running" >&2
    echo "  the Windows agent holds the card; nothing here can reach it without the bridge" >&2
    echo "  run: gpg-bridge-install --apply" >&2
    exit 1
  fi
}

# The agent answers for exactly one card: scdaemon on the Windows side binds to a
# single reader, so whatever it reports is the one that can be addressed. This
# replaces the macOS ykman count, which cannot run here and would add a dependency
# to answer a question the agent has already answered.
card_serial() {
  gpg --card-status --with-colons 2>/dev/null | grep '^serial:' | head -1 | cut -d: -f2
}

require_one_card() {
  require_bridge

  serial=$(card_serial)
  if [ -z "$serial" ]; then
    echo "ERROR: the agent reports no card" >&2
    echo "  check the key is in the dock, and that Windows gpg-agent is running:" >&2
    echo "    gpg --card-status" >&2
    exit 1
  fi

  # This card reports the serial unpadded, matching the printed one in the lib.
  # Stripped anyway: the AID in the same output does pad it, so a future gpg
  # reporting the padded form would otherwise fail the match for no real reason.
  serial=$(echo "$serial" | sed 's/^0*//')
  case "$serial" in
    "$YUBIKEY_A_SERIAL"|"$YUBIKEY_B_SERIAL"|"$YUBIKEY_C_SERIAL")
      echo "  card $serial" ;;
    *)
      echo "ERROR: card $serial is not one of the three in yubikeys.sh" >&2
      exit 1 ;;
  esac
}

# Reads the public key off the card and imports it, checking the fingerprint
# first. gpg-card would do this in one step and Ubuntu does not ship it, so the
# same bytes are fetched through the agent instead: SCD READCERT returns the DER
# container, whose only OCTET STRING is the keyblock. The offset is read from the
# parse rather than hardcoded, so a differently sized key still lands.
import_pubkey_from_card() {
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT INT TERM

  if ! gpg-connect-agent --no-autostart "/datafile $tmp/cert.der" \
      "SCD READCERT OPENPGP.$CERT_SLOT" /bye >/dev/null 2>&1; then
    echo "ERROR: could not read slot $CERT_SLOT from the card" >&2
    exit 1
  fi

  if [ ! -s "$tmp/cert.der" ]; then
    echo "ERROR: slot $CERT_SLOT is empty" >&2
    echo "  write the public key to it from a machine with gpg-card:" >&2
    echo "    gpg-card --no-history writecert --openpgp OPENPGP.$CERT_SLOT <fingerprint>" >&2
    exit 1
  fi

  offset=$(openssl asn1parse -inform DER -in "$tmp/cert.der" 2>/dev/null \
    | grep 'OCTET STRING' | head -1 | cut -d: -f1 | tr -d ' ')
  if [ -z "$offset" ]; then
    echo "ERROR: slot $CERT_SLOT does not hold the container gpg-card writes" >&2
    exit 1
  fi

  if ! openssl asn1parse -inform DER -in "$tmp/cert.der" -strparse "$offset" \
      -noout -out "$tmp/keyblock.pgp" 2>/dev/null; then
    echo "ERROR: could not unwrap the keyblock from slot $CERT_SLOT" >&2
    exit 1
  fi

  fpr=$(gpg --no-options --with-colons --show-keys "$tmp/keyblock.pgp" 2>/dev/null \
    | grep '^fpr' | head -1 | cut -d: -f10)
  if [ -z "$fpr" ]; then
    echo "ERROR: slot $CERT_SLOT is not an OpenPGP key" >&2
    exit 1
  fi

  # Checked before the import below, which marks whatever arrives as ultimately trusted.
  if [ "$fpr" != "$GPG_FINGERPRINT" ]; then
    echo "ERROR: this card holds $fpr" >&2
    echo "       expected $GPG_FINGERPRINT" >&2
    exit 1
  fi

  gpg --no-options --quiet --import "$tmp/keyblock.pgp"
  echo "  imported $fpr from the card"

  # Trust is per machine and does not travel with the key.
  printf '%s:6:\n' "$fpr" | gpg --no-options --quiet --import-ownertrust
  echo "  marked ultimately trusted"

  # Builds the stubs that point gpg at the card, now that it has the public half.
  gpg --card-status >/dev/null
  echo "  card stubs created"
}

test_sign() {
  require_one_card

  echo "Testing sign with $GPG_FINGERPRINT through the bridge..."
  if echo "banana" | gpg --no-options --local-user "$GPG_FINGERPRINT" --clearsign >/dev/null 2>&1; then
    echo "Signing works."
  else
    echo "Signing failed."
    echo "  if the key is present but signing fails, the PIN prompt appears on Windows" >&2
    exit 1
  fi
}

configure() {
  for arg in "$@"; do
    case "$arg" in
      # Accepted and ignored: there is no on-disk key mode here, and no local
      # scdaemon whose touch timeout could be configured. Taking the flag keeps
      # one command working on both machines.
      --hardware|--touch) ;;
      *) echo "ERROR: unknown option: $arg" >&2; exit 64 ;;
    esac
  done

  echo "GPG Configuration (WSL, card via the Windows agent)"
  echo "==================================================="
  echo ""

  require_one_card

  # Without this gpg starts its own agent whenever the socket is missing, so a
  # stopped bridge reports an absent card instead of an absent bridge.
  if [ -f "$GPG_CONF" ] && grep -qx 'no-autostart' "$GPG_CONF"; then
    echo "  gpg.conf: no-autostart already set"
  else
    mkdir -p "$(dirname "$GPG_CONF")"
    chmod 700 "$(dirname "$GPG_CONF")"
    echo 'no-autostart' >> "$GPG_CONF"
    echo "  gpg.conf: no-autostart added"
  fi

  if gpg --list-keys "$GPG_FINGERPRINT" >/dev/null 2>&1; then
    echo "  public key already present"
  else
    import_pubkey_from_card
  fi

  echo ""
  echo "Done. Signing uses the Windows pinentry; the PIN prompt appears there."
}

reset_bridge() {
  echo "Restarting $SERVICE..."
  systemctl --user restart "$SERVICE"
  echo "Done. The Windows agent keeps its own PIN cache; this only re-dials it."
}

schedule() {
  echo "Not applicable under WSL."
  echo ""
  echo "  The macOS version schedules a daily 'gpgconf --kill gpg-agent' to bound"
  echo "  the passphrase cache window. There is no local agent here to kill: the"
  echo "  cache belongs to the Windows agent, and the card clears its own verified"
  echo "  state when it leaves the dock. Set the TTL on the Windows side instead."
  exit 1
}

case "${1:-}" in
  --test-sign)  shift; test_sign "$@" ;;
  --configure)  shift; configure "$@" ;;
  --reset)      reset_bridge ;;
  --schedule)   schedule ;;
  *)            usage ;;
esac
