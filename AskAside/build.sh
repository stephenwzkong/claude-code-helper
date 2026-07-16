#!/bin/bash
# Build AskAside.app from the SwiftPM executable and ad-hoc sign it.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/AskAside"
APP="AskAside.app"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AskAside"
cp Info.plist "$APP/Contents/Info.plist"

# Prefer the stable self-signed identity (see setup-dev-cert.sh) so rebuilds keep the
# Accessibility grant. Fall back to ad-hoc if it isn't set up.
SIGN_ID="AskAside Dev"
# Note: a self-signed dev cert is untrusted, so it appears under `find-identity` (all)
# but NOT under `find-identity -p codesigning` (trusted only). codesign uses it fine.
if security find-identity 2>/dev/null | grep -q "$SIGN_ID"; then
  echo "==> Signing with stable identity '$SIGN_ID'"
  codesign --force --deep --sign "$SIGN_ID" "$APP"
else
  echo "==> Signing (ad-hoc; run ./setup-dev-cert.sh once to stop re-granting Accessibility)"
  codesign --force --deep --sign - "$APP"
fi

echo "Built $APP"
echo "Launch with:  open \"$PWD/$APP\""
