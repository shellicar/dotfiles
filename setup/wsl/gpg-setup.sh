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
# gpg-agent has no infinite value: the man page defines both TTLs as plain
# seconds, and 0 means no caching at all rather than never expiring. 400 days is
# the stand-in, since the agent dies at logout long before it elapses.
CACHE_TTL_HARDWARE=34560000

# No --generate here: key generation is always on-card, identical regardless
# of OS (see docs/yubikey.md), and is not needed from WSL.

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
  echo "  --reset        Restart the bridge and reload the Windows agent"
  echo "                 (next sign prompts for the PIN)"
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
    echo "ERROR: no data came back for slot $CERT_SLOT" >&2
    echo "  confirm with gpg --card-status before writing to the card; if the slot really is empty:" >&2
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

  # Without no-autostart, gpg silently starts a keyless local agent instead
  # of reaching the card through the bridge.
  if ! { [ -f "$GPG_CONF" ] && grep -qx 'no-autostart' "$GPG_CONF"; }; then
    echo "ERROR: gpg.conf does not have no-autostart set" >&2
    echo "  run gpg-setup.sh --configure first" >&2
    exit 1
  fi

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
        echo "ERROR: --touch is not supported on WSL: keep-chv-on-timeout needs a patched scdaemon," >&2
        echo "  and the Windows scdaemon is not known to be patched" >&2
        exit 64 ;;
      *) echo "ERROR: unknown option: $arg" >&2; exit 64 ;;
    esac
  done

  echo "GPG Configuration (WSL, card via the Windows agent)"
  echo "==================================================="
  echo ""

  require_one_card

  # A daily kill in cron reaches the Windows agent through the bridge too.
  if crontab -l 2>/dev/null | grep -q 'gpgconf --kill gpg-agent'; then
    crontab -l 2>/dev/null | grep -v 'gpgconf --kill gpg-agent' | crontab -
    echo "  Removed the daily gpg-agent kill from cron"
  else
    echo "  no leftover cron entry"
  fi

  mkdir -p "$(dirname "$GPG_CONF")"
  chmod 700 "$(dirname "$GPG_CONF")"

  # Without no-autostart, gpg starts a keyless local agent when the bridge is down.
  if [ -f "$GPG_CONF" ] && grep -qx 'no-autostart' "$GPG_CONF"; then
    echo "  gpg.conf: no-autostart already set"
  else
    # Without a final newline the option would join the file's last line.
    if [ -s "$GPG_CONF" ] && [ -n "$(tail -c 1 "$GPG_CONF")" ]; then
      echo >> "$GPG_CONF"
    fi
    echo 'no-autostart' >> "$GPG_CONF"
    echo "  gpg.conf: no-autostart added"
  fi

  # Written whole on every run, because --configure is the file's only source.
  # Without it the Windows agent runs its out-of-the-box cache (10 minutes /
  # 2 hours); the card should only need its PIN once.
  win_agent_conf="$(wslpath -u "$(wslvar APPDATA)")/gnupg/gpg-agent.conf"
  mkdir -p "$(dirname "$win_agent_conf")"
  cat > "$win_agent_conf" <<EOF
default-cache-ttl $CACHE_TTL_HARDWARE
max-cache-ttl $CACHE_TTL_HARDWARE
EOF
  echo "  Windows gpg-agent cache: ${CACHE_TTL_HARDWARE}s (agent lifetime, in practice)"
  echo "  config: $win_agent_conf"

  if gpg --list-keys "$GPG_FINGERPRINT" >/dev/null 2>&1; then
    echo "  public key already present"
    # Trust is per machine and does not travel with the key.
    printf '%s:6:\n' "$GPG_FINGERPRINT" | gpg --no-options --quiet --import-ownertrust
    echo "  marked ultimately trusted"
  else
    import_pubkey_from_card
  fi

  # Reaches the Windows agent through the bridge and makes it re-read
  # gpg-agent.conf without stopping it. A kill would stop it, and nothing
  # restarts it; see docs/yubikey.md. The card stays unlocked, since scdaemon
  # keeps it so; --reset is what relocks it.
  gpg-connect-agent --no-autostart reloadagent /bye 2>/dev/null || true
  echo "  Agent reloaded."

  echo ""
  echo "Done. Signing uses the Windows pinentry; the PIN prompt appears there."
}

reset_bridge() {
  echo "Restarting $SERVICE..."
  systemctl --user restart "$SERVICE"
  # Reloaded rather than killed, for the reason given in configure.
  # TODO(undecided): a failure of either command below ends --reset under
  # set -e, as a failed kill does in the macOS reset; the alternative is
  # configure's `|| true`.
  gpg-connect-agent --no-autostart reloadagent /bye
  # The card stays unlocked while scdaemon holds it, and a reload does not
  # restart scdaemon. Killed through the bridge, only the Windows scdaemon
  # stops; the agent starts a fresh one on the next card use, which asks for
  # the PIN.
  gpgconf --kill scdaemon
  echo "Done. Next sign will prompt for the PIN again."
}

schedule() {
  echo "Not applicable under WSL."
  echo ""
  echo "  The macOS version schedules a daily 'gpgconf --kill gpg-agent' to bound"
  echo "  how long an on-disk key's decrypted passphrase stays cached. WSL is"
  echo "  hardware-only, and --configure already sets a ~400-day cache TTL on the"
  echo "  Windows agent, so a daily forced re-auth has nothing to protect here."
  exit 1
}

case "${1:-}" in
  --test-sign)  shift; test_sign "$@" ;;
  --configure)  shift; configure "$@" ;;
  --reset)      reset_bridge ;;
  --schedule)   schedule ;;
  *)            usage ;;
esac
