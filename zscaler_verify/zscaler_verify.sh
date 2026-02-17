#!/bin/sh
# Verify Zscaler Root CA compliance with OpenSSL 3.x strict mode

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENSSL=/opt/homebrew/opt/openssl@3/bin/openssl
ROOT_CA="$SCRIPT_DIR/root-ca.pem"
INTERMEDIATE="$SCRIPT_DIR/intermediate-ca.pem"

echo "=== OpenSSL Version ==="
"$OPENSSL" version
echo ""

echo "=== Root CA ==="
"$OPENSSL" x509 -in "$ROOT_CA" -noout -subject -dates -fingerprint -sha256
echo ""

echo "=== Intermediate CA ==="
"$OPENSSL" x509 -in "$INTERMEDIATE" -noout -subject -dates -fingerprint -sha256
echo ""

echo "=== Verifying Zscaler Root CA (strict mode) ==="
"$OPENSSL" verify -x509_strict \
  -CAfile "$ROOT_CA" \
  "$INTERMEDIATE"
