#!/bin/bash
# One-time: create a STABLE self-signed code-signing identity so local rebuilds keep the
# same code identity. That means macOS keeps the Accessibility (TCC) grant across rebuilds,
# instead of forgetting it every time an ad-hoc signature changes.
#
# The cert is only used to sign locally — it is NOT trusted by Gatekeeper and does not need
# to be. codesign can sign with an untrusted self-signed identity just fine.
set -euo pipefail
cd "$(dirname "$0")"

CERT_NAME="AskAside Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
P12_PASS="askaside"
# Apple's LibreSSL produces PKCS12 that macOS `security` can import; some Homebrew/conda
# OpenSSL builds create p12s Apple can't read ("MAC verification failed").
OPENSSL="/usr/bin/openssl"; [ -x "$OPENSSL" ] || OPENSSL="openssl"

# A self-signed (untrusted) identity lists under `find-identity` but not `-p codesigning`.
if security find-identity 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "Signing identity '$CERT_NAME' already exists. Nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $CERT_NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "==> Generating self-signed code-signing cert"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -config "$TMP/cert.cnf"

"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout "pass:$P12_PASS" -name "$CERT_NAME"

echo "==> Importing into login keychain (allowing codesign to use it)"
# -A allows all apps to use the key, so codesign never prompts on each build.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -A -T /usr/bin/codesign

echo "Created signing identity '$CERT_NAME'."
echo "Now run ./build.sh — it will sign with this identity automatically."
