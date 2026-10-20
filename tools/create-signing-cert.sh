#!/bin/bash
# Creates a free, self-signed code-signing certificate for Dynamic Notch releases.
#
# Not a substitute for an Apple Developer ID: downloads still need "Open Anyway" on first launch.
# What it buys you: every release is signed by the same identity, so macOS keeps the Accessibility
# permission across updates instead of treating each build as a brand-new app.
#
# Usage:
#   tools/create-signing-cert.sh            # create cert in ~/.dynamicnotch-signing
#   tools/create-signing-cert.sh --upload   # also store it as GitHub Actions secrets (needs gh)
#   tools/create-signing-cert.sh --login    # also import into your login keychain for local builds
#
# Keep ~/.dynamicnotch-signing private and backed up: losing it means users re-grant permissions once.
set -euo pipefail

NAME="Dynamic Notch Self-Signed"
DIR="$HOME/.dynamicnotch-signing"
P12="$DIR/signing.p12"

if [[ -f "$P12" ]]; then
    echo "Certificate already exists at $P12 (reusing it)."
    PASSWORD="$(cat "$DIR/p12-password")"
else
    mkdir -p "$DIR" && chmod 700 "$DIR"
    PASSWORD="$(openssl rand -base64 24)"
    printf '%s' "$PASSWORD" > "$DIR/p12-password"

    cat > "$DIR/codesign.cnf" <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -config "$DIR/codesign.cnf" 2>/dev/null

    # -legacy keeps the PKCS#12 readable by macOS `security import` (OpenSSL 3 defaults are not).
    LEGACY=(-legacy)
    openssl pkcs12 -help 2>&1 | grep -q -- '-legacy' || LEGACY=()
    openssl pkcs12 -export "${LEGACY[@]}" -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
        -name "$NAME" -out "$P12" -passout "pass:$PASSWORD"
    chmod 600 "$DIR"/*
    echo "Created $P12 (valid 10 years)."
fi

for arg in "$@"; do
    case "$arg" in
        --upload)
            base64 -i "$P12" | gh secret set SIGNING_CERT_P12
            printf '%s' "$PASSWORD" | gh secret set SIGNING_CERT_PASSWORD
            printf '%s' "$NAME" | gh secret set SIGNING_IDENTITY
            echo "Uploaded SIGNING_CERT_P12, SIGNING_CERT_PASSWORD, SIGNING_IDENTITY to GitHub secrets."
            ;;
        --login)
            security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASSWORD" -T /usr/bin/codesign
            echo "Imported into login keychain. Build locally with:"
            echo "  CODESIGN_IDENTITY=\"$NAME\" ./build_app.sh"
            ;;
    esac
done
