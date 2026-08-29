#!/bin/sh
set -e

# --- Configuration ---
GPG_AGENT_CONF="$HOME/.gnupg/gpg-agent.conf"
GPG_CONF="$HOME/.gnupg/gpg.conf"
SCDAEMON_CONF="$HOME/.gnupg/scdaemon.conf"
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
  echo "                 Test signing with the key on the inserted card"
  echo "  --configure    Configure gpg-agent, keychain, and pinentry"
  echo "  --configure --hardware"
  echo "                 As above, but for card-only use: no cache expiry,"
  echo "                 and removes the daily kill from cron"
  echo "  --schedule     Set up daily cron to kill gpg-agent (default 6am)"
  echo "  --reset        Kill gpg-agent now (next sign prompts)"
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

# The signature key on the inserted card, which is unambiguous in a way an email
# lookup no longer is: every identity now resolves to the same key, and several
# card stubs carry the same addresses.
find_card_key() {
  gpg --no-options --card-status --with-colons 2>/dev/null \
    | awk -F: '/^fpr:/ { print $2; exit }'
}

test_sign() {
  if [ "${1:-}" = "--hardware" ]; then
    key_id=$(find_card_key)
    if [ -z "$key_id" ]; then
      echo "Error: no card inserted, or it holds no signature key"
      exit 1
    fi
    label="card"
  else
    printf "Email: "
    read -r email

    if [ -z "$email" ]; then
      echo "Error: email is required"
      exit 1
    fi

    key_id=$(find_key_by_email "$email")

    if [ -z "$key_id" ]; then
      echo "Error: no key found for $email"
      exit 1
    fi
    label="$email"
  fi

  echo "Testing sign with key $key_id ($label)..."
  echo "A card key needs a touch; the contact blinks and times out unanswered."
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
  if crontab -l 2>/dev/null | grep -q "/opt/homebrew/bin/gpgconf --kill gpg-agent"; then
    echo "  Existing cron entry found. Replacing..."
    crontab -l 2>/dev/null | grep -v "/opt/homebrew/bin/gpgconf --kill gpg-agent" | { cat; echo "$cron_line"; } | crontab -
  else
    { crontab -l 2>/dev/null; echo "$cron_line"; } | crontab -
  fi

  echo "  Scheduled: kill gpg-agent at $(printf '%02d:%02d' "$CRON_HOUR" "$CRON_MINUTE") daily"
  echo "  First commit after reset will prompt for passphrase."
  echo ""
  echo "Done."
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
  echo "Killing gpg-agent..."
  gpgconf --kill gpg-agent
  echo "Done. Next sign will prompt for passphrase."
}

# --hardware writes the card-only policy. A cached passphrase is not what stands
# between malware and a signature once the key is on a card: the touch is, and
# the chip enforces it regardless of cache state. So the TTL becomes purely how
# often the passphrase is typed, and the daily kill is bounding a window that no
# longer exists. Both only make sense while on-disk keys are still in use.
configure_agent() {
  if [ "${1:-}" = "--hardware" ]; then
    CACHE_TTL="$CACHE_TTL_HARDWARE"
    hardware=1
  else
    hardware=0
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
    # Without this, a touch that times out makes scdaemon de-verify the card and
    # discard the cached passphrase, so the next signature prompts again. The
    # card keeps PW1 verified on its own; only scdaemon throws it away. Needs the
    # patched build from setup/macos/build-gnupg.sh.
    if grep -q 'keep-chv-on-timeout' "$SCDAEMON_CONF" 2>/dev/null; then
      echo "  scdaemon: keep-chv-on-timeout already set"
    else
      echo "keep-chv-on-timeout" >> "$SCDAEMON_CONF"
      echo "  scdaemon: keep-chv-on-timeout added"
    fi
    remove_cron
  fi
  echo ""

  # --- gpg.conf ---
  if [ ! -f "$GPG_CONF" ] || ! grep -q "no-tty" "$GPG_CONF" 2>/dev/null; then
    echo "no-tty" >> "$GPG_CONF"
  fi

  # Reload agent
  gpg-connect-agent reloadagent /bye 2>/dev/null || true
  echo "  Agent reloaded."
  echo ""
  echo "Done. First sign will prompt for passphrase -- save it to the '$KEYCHAIN_NAME' keychain."
}

# --- Main ---
case "${1:-}" in
  --generate)   generate_key ;;
  --test-sign)  test_sign "${2:-}" ;;
  --configure)  configure_agent "${2:-}" ;;
  --schedule)   schedule_reset ;;
  --reset)      reset_agent ;;
  *)            usage ;;
esac
