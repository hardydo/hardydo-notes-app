#!/bin/bash
# Creates a self-signed code-signing identity so every build has the same signature
# and macOS keeps treating each rebuild as the same app.
set -euo pipefail

name="${HARDYDO_SIGN_IDENTITY:-Hardydo Notes Dev}"
keychain="${1:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -p codesigning "$keychain" | grep -q "\"$name\""; then
    echo "\"$name\" already exists in $keychain"
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cert.conf" \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
transfer="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
    -name "$name" -out "$work/identity.p12" -passout "pass:$transfer"
security import "$work/identity.p12" -k "$keychain" -P "$transfer" -T /usr/bin/codesign >/dev/null

echo "Created \"$name\" in $keychain"
