#!/bin/sh

CERT_PATH="./ZScalerRootCA.pem"

update_linux_certs() {
    echo "Linux detected - updating CA certificates..."
    CA_CERTS_DIR="/usr/local/share/ca-certificates"
    sudo cp "$CERT_PATH" "$CA_CERTS_DIR/ZScalerRootCA.crt"
    sudo update-ca-certificates
}

update_macos_certs() {
    echo "macOS detected - updating Homebrew CA bundle..."
    
    if !  command -v brew >/dev/null 2>&1; then
        echo "Error: Homebrew not found"
        exit 1
    fi
    
    brew list ca-certificates >/dev/null 2>&1 || brew install ca-certificates
    
    CA_BUNDLE="$(brew --prefix)/etc/ca-certificates/cert.pem"
    cat "$CERT_PATH" | sudo tee -a "$CA_BUNDLE" > /dev/null
    
    echo "✓ Certificate added to Homebrew CA bundle"
}

if [ ! -f "$CERT_PATH" ]; then
    echo "Certificate file not found: $CERT_PATH"
    exit 1
fi

OS=$(uname)

case $OS in
Linux)
    update_linux_certs
    ;;
Darwin)
    update_macos_certs
    ;;
*)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac
