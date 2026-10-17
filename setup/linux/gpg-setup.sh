#!/bin/sh
#
# GPG setup, standard Linux: the parts setup/wsl/gpg-setup.sh builds on. It is
# not a complete Linux setup: there is no gpg-agent.conf or pinentry here, only
# what WSL also uses.
#
# setup/wsl/gpg-setup.sh sources this with GPG_SETUP_SOURCED=1, redefines what
# differs on WSL, and runs its own dispatch. Each step is a linux_* function, and
# the plain name calls it, so WSL can replace the plain name and still reach the
# Linux step.
# TODO(claude): undecided: how the WSL setup reuses this file. Sourcing it under
# a flag that skips the dispatch, then redefining functions, for now.

set -eu

# The directory of the script that was run: setup/linux, or setup/wsl when
# sourced. Both sit at the same depth, so the paths below hold for either.
DIR=$(cd "$(dirname "$0")" && pwd)

# GPG_FINGERPRINT and the YubiKey serials.
LIB="$DIR/../../home/common/lib/yubikeys.sh"
[ -f "$LIB" ] || { echo "ERROR: $LIB not found" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../gpg-common.sh
. "$DIR/../gpg-common.sh"

GPG_CONF="${GNUPGHOME:-$HOME/.gnupg}/gpg.conf"
CERT_SLOT=3

# --- The card ---

# Whatever has to be up before the agent can answer for the card. Nothing on
# Linux, where gpg starts the agent itself.
require_agent() { :; }

# The serial of the card gpg --card-status reports. gpg 2.3+ can see several
# cards; this is the one it currently addresses.
card_serial() {
  gpg --card-status --with-colons 2>/dev/null | grep '^serial:' | head -1 | cut -d: -f2
}

# Checks a card answers, and it is one of the three in yubikeys.sh. It does not
# count the cards.
require_one_card() {
  require_agent

  serial=$(card_serial)
  if [ -z "$serial" ]; then
    echo "ERROR: the agent reports no card" >&2
    echo "  check the key is in the dock, then: gpg --card-status" >&2
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

# --- Commands ---

# What must hold before a test signature means anything, beyond the card.
# Nothing on Linux.
test_sign_check() { :; }

linux_test_sign() {
  require_one_card
  test_sign_check

  echo "Testing sign with $GPG_FINGERPRINT..."
  if echo "banana" | gpg --no-options --local-user "$GPG_FINGERPRINT" --clearsign >/dev/null 2>&1; then
    echo "Signing works."
  else
    echo "Signing failed."
    return 1
  fi
}
test_sign() { linux_test_sign "$@" || exit 1; }

# The configuration files. Neither the agent nor the card is used.
linux_configure_files() {
  # The PIN is asked for only in the configured pinentry window, never in a
  # terminal.
  ensure_conf_line "$GPG_CONF" no-tty
}

# The public key, last because it is the only step that can need the card. A key
# already in the keyring is only re-marked as trusted, without the card.
linux_configure_key() {
  if gpg --list-keys "$GPG_FINGERPRINT" >/dev/null 2>&1; then
    echo "  public key already present"
    # Trust is per machine and does not travel with the key.
    printf '%s:6:\n' "$GPG_FINGERPRINT" | gpg --no-options --quiet --import-ownertrust
    echo "  marked ultimately trusted"
  else
    echo "  public key not in the keyring; reading it from the card"
    require_one_card
    import_pubkey_from_card
  fi
}

linux_configure() {
  for arg in "$@"; do
    case "$arg" in
      # Accepted so the macOS command line works here; the card is the only mode.
      --hardware) ;;
      *) echo "ERROR: unknown option: $arg" >&2; exit 64 ;;
    esac
  done

  echo "GPG Configuration (Linux)"
  echo "========================="
  echo ""
  linux_configure_files
  linux_configure_key
  echo ""
  echo "Done."
}
configure() { linux_configure "$@"; }

linux_reset() {
  echo "Restarting gpg-agent..."
  gpgconf --kill gpg-agent
  start_agent
  echo "Done. Next sign will prompt for the PIN again."
}
reset_agent() { linux_reset; }

# Installed and configured, read without changing anything and without the agent
# or the card.
linux_doctor_checks() {
  echo "Installed"
  for cmd in gpg gpgconf gpg-connect-agent openssl; do
    check_command "$cmd"
  done
  echo ""
  echo "Configured"
  check_conf_line "$GPG_CONF" no-tty "run: gpg-setup.sh --configure"
  check_public_key "$GPG_FINGERPRINT" "run: gpg-setup.sh --configure"
}
doctor_checks() { linux_doctor_checks; }

# $1 names the OS in the heading; the rest are the command's options.
doctor() {
  label="$1"
  shift
  for arg in "$@"; do
    case "$arg" in
      # Accepted so the macOS command line works here; the card is the only mode.
      --hardware) ;;
      *) echo "ERROR: unknown option: $arg" >&2; exit 64 ;;
    esac
  done

  echo "GPG signing check ($label)"
  echo ""
  doctor_checks
  doctor_verdict
}

linux_usage() {
  echo "Usage: $(basename "$0") <command>"
  echo ""
  echo "Commands:"
  echo "  --test-sign    Test signing with the key on the card"
  echo "  --configure    Configure this machine to sign with the card"
  echo "  --doctor       Check what is installed and configured, changing nothing"
  echo "  --doctor --hardware"
  echo "                 The same thing"
  echo "  --reset        Restart gpg-agent (next sign prompts for the PIN)"
  exit 1
}

[ "${GPG_SETUP_SOURCED:-0}" = 1 ] && return 0

case "${1:-}" in
  --test-sign)  shift; test_sign "$@" ;;
  --configure)  shift; configure "$@" ;;
  --doctor)     shift; doctor Linux "$@" ;;
  --reset)      reset_agent ;;
  *)            linux_usage ;;
esac
