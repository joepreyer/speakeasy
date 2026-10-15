#!/bin/bash
# Creates a local self-signed code signing certificate ("SpeakEasy Dev Signing") so local
# builds keep a stable identity. Without it, every rebuild looks like a new app to macOS and
# you have to grant Accessibility and Input Monitoring again.
#
# macOS asks for your password once to trust the certificate for code signing.
set -euo pipefail

NAME="SpeakEasy Dev Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "\"$NAME\" already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
# OpenSSL 3 needs -legacy for a PKCS#12 file the macOS keychain can import.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:speakeasy 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:speakeasy

security import "$TMP/cert.p12" -k "$KEYCHAIN" -P speakeasy -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "Created \"$NAME\". ./build.sh will use it automatically."
