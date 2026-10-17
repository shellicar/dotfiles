#!/bin/sh
set -e

# GPG_FINGERPRINT, so a key imported off a card is checked rather than taken on trust.
LIB="$(dirname "$0")/../../home/common/lib/yubikeys.sh"
[ -f "$LIB" ] || { echo "ERROR: $LIB not found" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

# start_agent, the gpg.conf helpers and the --doctor checks.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../gpg-common.sh
. "$(dirname "$0")/../gpg-common.sh"

# --- Configuration ---
GPG_AGENT_CONF="$HOME/.gnupg/gpg-agent.conf"
GPG_CONF="$HOME/.gnupg/gpg.conf"
SCDAEMON_CONF="$HOME/.gnupg/scdaemon.conf"
# The certificate references are storage separate from the key slots, despite
# sharing their numbering. Only reference 3 accepts an OpenPGP keyblock: 1 and 2
# are rejected with `Invalid argument`, and 4 with `CERTREF must be OPENPGP.N or
# just N with N being 1..3`. So the choice is not open.
CERT_SLOT=3
KEYCHAIN_NAME="gpg.keychain"
KEYCHAIN_PATH="$HOME/Library/Keychains/${KEYCHAIN_NAME}-db"
KEYCHAIN_TIMEOUT=1
CACHE_TTL=86400
# gpg-agent has no infinite value: the man page defines both TTLs as plain
# seconds, and 0 means no caching at all rather than never expiring. 400 days is
# the stand-in, since the agent dies at logout long before it elapses.
CACHE_TTL_HARDWARE=34560000
CRON_HOUR="${CRON_HOUR:-6}"
CRON_MINUTE="${CRON_MINUTE:-0}"

# --- Helpers ---
usage() {
  echo "Usage: $(basename "$0") <command>"
  echo ""
  echo "Commands:"
  echo "  --test-sign    Test signing with an on-disk key (prompts for email)"
  echo "  --test-sign --hardware"
  echo "                 Test signing with the key on the inserted card."
  echo "                 Needs exactly one inserted"
  echo "  --configure    Configure gpg-agent, keychain, and pinentry"
  echo "  --configure --hardware"
  echo "                 As above, but for card-only use: no cache expiry,"
  echo "                 removes the daily kill from cron, and imports the"
  echo "                 public key from the card. Needs exactly one inserted"
  echo "  --configure --hardware --touch"
  echo "                 As above, plus scdaemon's keep-chv-on-timeout, for a"
  echo "                 card whose sig slot has a touch policy"
  echo "  --schedule     Set up daily cron to kill gpg-agent (default 6am)"
  echo "  --doctor       Check what --configure set up, changing nothing"
  echo "  --doctor --hardware"
  echo "                 Check what --configure --hardware set up, changing nothing"
  echo "  --reset        Restart gpg-agent (next sign prompts)"
  exit 1
}

find_key_by_email() {
  email="$1"
  gpg --list-secret-keys --keyid-format long "$email" 2>/dev/null \
    | grep -m1 'sec' \
    | sed 's/.*\/\([A-F0-9]\{16\}\).*/\1/'
}

generate_key() {
  echo "Disabled. Signing keys are generated on-card, which cannot be scripted:"
  echo ""
  echo "  gpg --no-options --card-edit"
  echo "  admin"
  echo "  key-attr      # ECC, Curve 25519, for each of the three slots"
  echo "  generate      # no off-card backup, no expiry"
  echo ""
  echo "See docs/yubikey.md. Re-enable this only to make an on-disk key."
  exit 1
}

# The signature key on the inserted card. Unambiguous in a way an email lookup is
# not: every identity resolves to the same key, and several card stubs carry the
# same addresses.
find_card_key() {
  gpg --no-options --card-status --with-colons 2>/dev/null \
    | awk -F: '/^fpr:/ { print $2; exit }'
}

test_sign() {
  if [ "${1:-}" = "--hardware" ]; then
    require_one_card
    key_id=$(find_card_key)
    if [ -z "$key_id" ]; then
      echo "ERROR: the inserted card holds no signature key" >&2
      exit 1
    fi
    label="card"
  else
    printf "Email: "
    read -r email

    if [ -z "$email" ]; then
      echo "ERROR: email is required" >&2
      exit 1
    fi

    key_id=$(find_key_by_email "$email")

    if [ -z "$key_id" ]; then
      echo "ERROR: no key found for $email" >&2
      exit 1
    fi
    label="$email"
  fi

  echo "Testing sign with key $key_id ($label)..."
  if echo "banana" | gpg --no-options --local-user "$key_id" --clearsign > /dev/null 2>&1; then
    echo "Signing works."
  else
    echo "Signing failed."
    exit 1
  fi
}

schedule_reset() {
  echo "GPG Agent Scheduled Reset"
  echo "========================="
  echo ""

  cron_line="$CRON_MINUTE $CRON_HOUR * * * gpgconf --kill gpg-agent"

  # Check if already scheduled
  if crontab -l 2>/dev/null | grep -q "gpgconf --kill gpg-agent"; then
    echo "  Existing cron entry found. Replacing..."
    crontab -l 2>/dev/null | grep -v "gpgconf --kill gpg-agent" | { cat; echo "$cron_line"; } | crontab -
  else
    { crontab -l 2>/dev/null; echo "$cron_line"; } | crontab -
  fi

  echo "  Scheduled: kill gpg-agent at $(printf '%02d:%02d' "$CRON_HOUR" "$CRON_MINUTE") daily"
  echo "  First commit after reset will prompt for passphrase."
  echo ""
  echo "Done."
}

# Exactly one card, or the operation is ambiguous: scdaemon binds to a single
# card, so with two inserted the commands below would silently address whichever
# it picked.
require_one_card() {
  if ! command -v ykman >/dev/null 2>&1; then
    echo "ERROR: ykman not found; install it with 'brew install ykman'" >&2
    exit 1
  fi

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
}

# The '>' is quoted because gpg-card parses it, not the shell.
read_cert_openpgp() {
  gpg-card --no-history readcert --openpgp "$CERT_SLOT" '>' /dev/stdout 2>/dev/null \
    | base64
}

read_cert_raw_size() {
  gpg-card --no-history readcert "$CERT_SLOT" '>' /dev/stdout | wc -c | tr -d ' '
}

import_pubkey_from_card() {
  key=$(read_cert_openpgp)

  if [ -z "$key" ]; then
    bytes=$(read_cert_raw_size)
    if [ "$bytes" -lt 16 ]; then
      echo "ERROR: no public key on this card ($bytes bytes in the slot)" >&2
      echo "  write one with:" >&2
    else
      echo "ERROR: this card holds $bytes bytes in the slot, but not the" >&2
      echo "       container gpg-card writes" >&2
      echo "  overwrite it with:" >&2
    fi
    echo "  gpg-card --no-history writecert --openpgp OPENPGP.$CERT_SLOT <fingerprint>" >&2
    exit 1
  fi

  fpr=$(printf '%s' "$key" | base64 -d \
    | gpg --no-options --with-colons --show-keys 2>/dev/null \
    | awk -F: '/^fpr:/ { print $10; exit }')
  if [ -z "$fpr" ]; then
    echo "ERROR: the card's certificate object is not an OpenPGP key" >&2
    exit 1
  fi

  # Checked before the import below, which marks whatever arrives as ultimately trusted.
  if [ "$fpr" != "$GPG_FINGERPRINT" ]; then
    echo "ERROR: this card holds $fpr" >&2
    echo "       expected $GPG_FINGERPRINT" >&2
    exit 1
  fi

  printf '%s' "$key" | base64 -d | gpg --no-options --quiet --import
  echo "  imported $fpr from the card"

  # Trust is per machine and does not travel with the key.
  printf '%s:6:\n' "$fpr" | gpg --no-options --quiet --import-ownertrust

  # Builds the stub that points gpg at the card.
  gpg --no-options --card-status >/dev/null
  echo "  card stub created"
}

remove_cron() {
  if crontab -l 2>/dev/null | grep -q 'gpgconf --kill gpg-agent'; then
    crontab -l 2>/dev/null | grep -v 'gpgconf --kill gpg-agent' | crontab -
    echo "  Removed the daily gpg-agent kill from cron"
  else
    echo "  No gpg-agent cron entry to remove"
  fi
}

reset_agent() {
  echo "Restarting gpg-agent..."
  gpgconf --kill gpg-agent
  start_agent
  echo "Done. Next sign will prompt for passphrase."
}

# --hardware writes the card-only policy. The TTL decides one thing: how often the
# passphrase is typed. 400 days means once. The daily kill bounds a cache window
# and only makes sense while on-disk keys are still in use.
configure_agent() {
  hardware=0
  touch_policy=0
  for arg in "$@"; do
    case "$arg" in
      --hardware) hardware=1 ;;
      --touch)    touch_policy=1 ;;
      *)          echo "ERROR: unknown option: $arg" >&2; exit 64 ;;
    esac
  done

  if [ "$hardware" -eq 1 ]; then
    CACHE_TTL="$CACHE_TTL_HARDWARE"
  fi

  echo "GPG Agent + Keychain Configuration"
  echo "===================================="
  if [ "$hardware" -eq 1 ]; then
    echo "Mode: hardware (card-only)"
  else
    echo "Mode: on-disk keys"
  fi
  echo ""

  # --- Keychain ---
  # 1. Check if file exists
  if [ -f "$KEYCHAIN_PATH" ]; then
    echo "  Keychain file exists: $KEYCHAIN_PATH"
  else
    echo "  Creating keychain '$KEYCHAIN_NAME'..."
    security create-keychain "$KEYCHAIN_NAME"
    echo "  Created: $KEYCHAIN_PATH"
  fi

  # Set lock timeout
  security set-keychain-settings -t "$KEYCHAIN_TIMEOUT" "$KEYCHAIN_PATH"
  echo "  Keychain timeout: ${KEYCHAIN_TIMEOUT}s"

  # 2. Check if it's in the search list, add if not
  if security list-keychains -d user | grep -q "$KEYCHAIN_NAME"; then
    echo "  Keychain in search list: yes"
  else
    echo "  Adding keychain to search list..."
    current_keychains=$(security list-keychains -d user | tr -d '"' | tr -d ' ' | tr '\n' ' ')
    security list-keychains -d user -s $current_keychains "$KEYCHAIN_PATH"
    echo "  Keychain in search list: added"
  fi

  # Point pinentry-mac at the gpg keychain
  defaults write org.gpgtools.common KeychainPath "$KEYCHAIN_PATH"
  echo "  org.gpgtools.common KeychainPath: $KEYCHAIN_PATH"
  echo ""

  # --- gpg-agent.conf ---
  mkdir -p "$HOME/.gnupg"
  chmod 700 "$HOME/.gnupg"

  cat > "$GPG_AGENT_CONF" <<EOF
default-cache-ttl $CACHE_TTL
max-cache-ttl $CACHE_TTL
EOF

  if command -v pinentry-mac > /dev/null 2>&1; then
    echo "pinentry-program $(command -v pinentry-mac)" >> "$GPG_AGENT_CONF"
    echo "  pinentry: $(command -v pinentry-mac)"
  fi

  if [ "$CACHE_TTL" -eq "$CACHE_TTL_HARDWARE" ]; then
    echo "  gpg-agent cache: ${CACHE_TTL}s (agent lifetime, in practice)"
  else
    echo "  gpg-agent cache: ${CACHE_TTL}s"
  fi
  echo "  config: $GPG_AGENT_CONF"

  if [ "$hardware" -eq 1 ]; then
    # Only with --touch, and only meaningful on a sig slot that has one. Written
    # before the card is read: reading it starts scdaemon, and reloading the
    # agent afterwards does not restart it, so a scdaemon spawned first would run
    # without this until it next exits.
    #
    # Without it, a touch that times out makes scdaemon de-verify the card and
    # discard the cached passphrase, so the next signature prompts again. The
    # card keeps PW1 verified on its own; only scdaemon throws it away. Needs a
    # patched scdaemon.
    if [ "$touch_policy" -eq 1 ]; then
      if [ -f "$SCDAEMON_CONF" ] && grep -q 'keep-chv-on-timeout' "$SCDAEMON_CONF"; then
        echo "  scdaemon: keep-chv-on-timeout already set"
      else
        if [ -s "$SCDAEMON_CONF" ] && [ -n "$(tail -c 1 "$SCDAEMON_CONF")" ]; then
          echo >> "$SCDAEMON_CONF"
        fi
        echo "keep-chv-on-timeout" >> "$SCDAEMON_CONF"
        echo "  scdaemon: keep-chv-on-timeout added"
      fi
    fi

    remove_cron
  fi
  echo ""

  # --- gpg.conf ---
  # The PIN is asked for only in pinentry-mac, never in a terminal.
  ensure_conf_line "$GPG_CONF" no-tty
  # gpg starts its own agent whenever it needs one, unless this turns it off.
  if has_conf_line "$GPG_CONF" no-autostart; then
    remove_conf_line "$GPG_CONF" no-autostart
    echo "  gpg.conf: no-autostart removed"
  else
    echo "  gpg.conf: autostart not turned off"
  fi

  # A running agent re-reads its configuration; one that is not running reads it
  # when it starts.
  if gpg-connect-agent --no-autostart reloadagent /bye >/dev/null 2>&1; then
    echo "  Agent reloaded."
  else
    echo "  Agent not running; it reads the configuration when it starts."
  fi

  # Last, because it is the only step that can need the card. A key already in
  # the keyring is only re-marked as trusted, without the card.
  if [ "$hardware" -eq 1 ]; then
    if gpg --no-options --list-keys "$GPG_FINGERPRINT" >/dev/null 2>&1; then
      echo "  public key already present"
      printf '%s:6:\n' "$GPG_FINGERPRINT" | gpg --no-options --quiet --import-ownertrust
      echo "  marked ultimately trusted"
    else
      require_one_card
      import_pubkey_from_card
    fi
  fi
  echo ""
  echo "Done. First sign will prompt for passphrase -- save it to the '$KEYCHAIN_NAME' keychain."
}

# Installed and configured, read without changing anything and without the agent
# or the card. Checks what --configure writes, or with --hardware what
# --configure --hardware writes.
doctor() {
  hardware=0
  for arg in "$@"; do
    case "$arg" in
      --hardware) hardware=1 ;;
      *)          echo "ERROR: unknown option: $arg" >&2; exit 64 ;;
    esac
  done

  if [ "$hardware" -eq 1 ]; then
    fix="run: gpg-setup.sh --configure --hardware"
    ttl_want="$CACHE_TTL_HARDWARE"
    echo "GPG signing check (macOS, hardware)"
  else
    fix="run: gpg-setup.sh --configure"
    ttl_want="$CACHE_TTL"
    echo "GPG signing check (macOS, on-disk keys)"
  fi
  echo ""
  echo "Installed"
  tools='gpg gpgconf gpg-connect-agent pinentry-mac'
  [ "$hardware" -eq 0 ] || tools="$tools gpg-card ykman"
  for cmd in $tools; do
    check_command "$cmd" "run: ./setup.sh"
  done

  echo ""
  echo "Configured"
  pinentry=$(command -v pinentry-mac 2>/dev/null || true)
  if [ -z "$pinentry" ]; then
    check_bad "no pinentry-program to check: pinentry-mac is not installed"
  elif has_conf_line "$GPG_AGENT_CONF" "pinentry-program $pinentry"; then
    check_ok "$GPG_AGENT_CONF uses $pinentry"
  else
    check_bad "$GPG_AGENT_CONF does not set pinentry-program $pinentry" "$fix"
  fi
  if has_conf_line "$GPG_AGENT_CONF" "default-cache-ttl $ttl_want" \
      && has_conf_line "$GPG_AGENT_CONF" "max-cache-ttl $ttl_want"; then
    check_ok "gpg-agent cache ${ttl_want}s"
  else
    check_bad "$GPG_AGENT_CONF does not set the cache TTL to ${ttl_want}s" "$fix"
  fi
  check_conf_line "$GPG_CONF" no-tty "$fix"
  if has_conf_line "$GPG_CONF" no-autostart; then
    check_bad "$GPG_CONF has no-autostart, so gpg will not start its agent" "$fix"
  else
    check_ok "gpg starts its own agent (no no-autostart in gpg.conf)"
  fi
  # The keychain's lock timeout is not checked: reading it with
  # `security show-keychain-info` asks for the keychain password in a terminal,
  # and fails over SSH with "User interaction is not allowed".
  if [ -f "$KEYCHAIN_PATH" ] && security list-keychains -d user | grep -q "$KEYCHAIN_NAME"; then
    check_ok "keychain $KEYCHAIN_NAME in the search list"
  else
    check_bad "keychain $KEYCHAIN_PATH missing or not in the search list" "$fix"
  fi
  if [ "$(defaults read org.gpgtools.common KeychainPath 2>/dev/null || true)" = "$KEYCHAIN_PATH" ]; then
    check_ok "pinentry-mac saves to the $KEYCHAIN_NAME keychain"
  else
    check_bad "org.gpgtools.common KeychainPath is not $KEYCHAIN_PATH" "$fix"
  fi

  if [ "$hardware" -eq 1 ]; then
    if crontab -l 2>/dev/null | grep -q 'gpgconf --kill gpg-agent'; then
      check_bad "cron still kills gpg-agent daily" "$fix"
    else
      check_ok "no daily gpg-agent kill in cron"
    fi
    check_public_key "$GPG_FINGERPRINT" "$fix"
  fi
  doctor_verdict
}

# --- Main ---
case "${1:-}" in
  --generate)   generate_key ;;
  --test-sign)  test_sign "${2:-}" ;;
  --configure)  shift; configure_agent "$@" ;;
  --schedule)   schedule_reset ;;
  --doctor)     shift; doctor "$@" ;;
  --reset)      reset_agent ;;
  *)            usage ;;
esac
