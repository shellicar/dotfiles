#!/bin/sh

CERT_PATH="./ZScalerRootCA.pem"
CA_CERTS_DIR="/usr/local/share/ca-certificates"

if [ ! -f "$CERT_PATH" ]; then
    echo "Certificate file not found: $CERT_PATH"
    exit 1
fi

sudo cp "$CERT_PATH" "$CA_CERTS_DIR/ZScalerRootCA.crt"
sudo update-ca-certificates
