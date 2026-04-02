#!/bin/sh
set -e

# --- Configuration ---
GPG_AGENT_CONF="$HOME/.gnupg/gpg-agent.conf"
GPG_CONF="$HOME/.gnupg/gpg.conf"
KEYCHAIN_NAME="gpg.keychain"
KEYCHAIN_PATH="$HOME/Library/Keychains/${KEYCHAIN_NAME}-db"
KEYCHAIN_TIMEOUT=1

# --- Helpers ---
usage() {
  echo "Usage: $(basename "$0") <command>"
  echo ""
  echo "Commands:"
  echo "  --generate     Generate a new GPG key (interactive)"
  echo "  --test-sign    Test signing with a key (prompts for email)"
  echo "  --configure    Configure gpg-agent, keychain, and pinentry"
  exit 1
}

find_key_by_email() {
  email="$1"
  gpg --list-secret-keys --keyid-format long "$email" 2>/dev/null \
    | grep -m1 'sec' \
    | sed 's/.*\/\([A-F0-9]\{16\}\).*/\1/'
}

generate_key() {
  echo "GPG Key Generation"
  echo "==================="
  echo ""
  echo "When prompted, select:"
  echo "  Kind:    (1) RSA and RSA"
  echo "  Size:    4096"
  echo "  Expiry:  your choice (0 = no expiry)"
  echo ""

  gpg --full-generate-key

  echo ""
  echo "Your keys:"
  gpg --list-secret-keys --keyid-format long
}

test_sign() {
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

  echo "Testing sign with key $key_id ($email)..."
  echo "banana" | gpg --local-user "$key_id" --clearsign > /dev/null 2>&1

  if [ $? -eq 0 ]; then
    echo "Signing works."
  else
    echo "Signing failed."
    exit 1
  fi
}

configure_agent() {
  echo "GPG Agent + Keychain Configuration"
  echo "===================================="
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
default-cache-ttl 0
max-cache-ttl 0
EOF

  if command -v pinentry-mac > /dev/null 2>&1; then
    echo "pinentry-program $(command -v pinentry-mac)" >> "$GPG_AGENT_CONF"
    echo "  pinentry: $(command -v pinentry-mac)"
  fi

  echo "  gpg-agent cache: disabled (TTL 0)"
  echo "  config: $GPG_AGENT_CONF"
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
  --test-sign)  test_sign ;;
  --configure)  configure_agent ;;
  *)            usage ;;
esac
