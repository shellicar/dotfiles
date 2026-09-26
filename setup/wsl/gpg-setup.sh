#!/bin/sh
#
# GPG setup, WSL. The card is held by the Windows gpg-agent and reached through
# gpg-bridge, so there is no local agent, pinentry or scdaemon to configure.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)

# GPG_FINGERPRINT and the YubiKey serials.
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

# To gpg, a stopped bridge looks the same as an absent card.
require_bridge() {
  if [ "$(systemctl --user is-active "$SERVICE" 2>/dev/null || true)" != active ]; then
    echo "ERROR: $SERVICE is not running" >&2
    echo "  the Windows agent holds the card; nothing here can reach it without the bridge" >&2
    echo "  run: gpg-bridge-install --apply" >&2
    exit 1
  fi
}

# The serial of the card gpg --card-status reports. gpg 2.3+ can see several
# cards; this is the one it currently addresses.
card_serial() {
  gpg --card-status --with-colons 2>/dev/null | grep '^serial:' | head -1 | cut -d: -f2
}

# Checks the bridge is up, a card answers, and it is one of the three in
# yubikeys.sh. It does not count the cards.
require_one_card() {
  require_bridge

  serial=$(card_serial)
  if [ -z "$serial" ]; then
    echo "ERROR: the agent reports no card" >&2
    echo "  check the key is in the dock, and that Windows gpg-agent is running:" >&2
    echo "    gpg --card-status" >&2
    exit 1
  fi

  # Leading zeros stripped in case gpg reports the padded form.
  serial=$(echo "$serial" | sed 's/^0*//')
  case "$serial" in
    "$YUBIKEY_A_SERIAL"|"$YUBIKEY_B_SERIAL"|"$YUBIKEY_C_SERIAL")
      echo "  card $serial" ;;
    *)
      echo "ERROR: card $serial is not one of the three in yubikeys.sh" >&2
      exit 1 ;;
  esac
}

# Ubuntu does not ship gpg-card, so the keyblock is read with SCD READCERT and
# taken from the only OCTET STRING in its DER container.
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

  # Builds the stubs that point gpg at the card.
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
      # Accepted so the macOS command line works here; nothing to configure.
      --hardware) ;;
      --touch)
        echo "ERROR: --touch is not supported on WSL: scdaemon runs on the Windows side" >&2
        exit 64 ;;
      *) echo "ERROR: unknown option: $arg" >&2; exit 64 ;;
    esac
  done

  echo "GPG Configuration (WSL, card via the Windows agent)"
  echo "==================================================="
  echo ""

  require_one_card

  # Without no-autostart, gpg starts a keyless local agent when the bridge is down.
  if [ -f "$GPG_CONF" ] && grep -qx 'no-autostart' "$GPG_CONF"; then
    echo "  gpg.conf: no-autostart already set"
  else
    mkdir -p "$(dirname "$GPG_CONF")"
    chmod 700 "$(dirname "$GPG_CONF")"
    # Without a final newline the option would join the file's last line.
    if [ -s "$GPG_CONF" ] && [ -n "$(tail -c 1 "$GPG_CONF")" ]; then
      echo >> "$GPG_CONF"
    fi
    echo 'no-autostart' >> "$GPG_CONF"
    echo "  gpg.conf: no-autostart added"
  fi

  if gpg --list-keys "$GPG_FINGERPRINT" >/dev/null 2>&1; then
    echo "  public key already present"
    # Trust is per machine and does not travel with the key.
    printf '%s:6:\n' "$GPG_FINGERPRINT" | gpg --no-options --quiet --import-ownertrust
    echo "  marked ultimately trusted"
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
