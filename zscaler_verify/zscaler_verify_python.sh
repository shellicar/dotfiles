#!/bin/sh
# Prove Zscaler Root CA fails with Azure CLI's Python (OpenSSL 3.x)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AZ_PYTHON=/opt/homebrew/Cellar/azure-cli/2.81.0/libexec/bin/python
ROOT_CA="$SCRIPT_DIR/root-ca.pem"

echo "=== Azure CLI Python OpenSSL Version ==="
"$AZ_PYTHON" -c "import ssl; print(ssl.OPENSSL_VERSION)"
echo ""

echo "=== Verifying SSL connection using Zscaler Root CA ==="
"$AZ_PYTHON" -c "
import ssl
import urllib.request

ctx = ssl.create_default_context()
ctx.load_verify_locations('$ROOT_CA')
req = urllib.request.Request('https://app.vssps.visualstudio.com/')
try:
    resp = urllib.request.urlopen(req, context=ctx)
    print('SUCCESS:', resp.status)
except Exception as e:
    print('FAILED:', e)
"
