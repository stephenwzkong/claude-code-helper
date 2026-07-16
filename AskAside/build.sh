#!/bin/bash
# Build AskAside.app as a UNIVERSAL binary (arm64 + x86_64) so it runs on both Apple
# Silicon and Intel Macs, then sign it.
#
# Note: `swift build --arch arm64 --arch x86_64` needs full Xcode (xcbuild). With only the
# Command Line Tools we build each slice separately and lipo them together.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
DEPLOY_TARGET="13.0"
APP="AskAside.app"

build_slice() { # arch -> prints binary path
  local arch="$1" scratch=".build-$1"
  swift build -c "$CONFIG" --scratch-path "$scratch" \
    -Xswiftc -target -Xswiftc "${arch}-apple-macos${DEPLOY_TARGET}" >&2
  echo "$(swift build -c "$CONFIG" --scratch-path "$scratch" \
    -Xswiftc -target -Xswiftc "${arch}-apple-macos${DEPLOY_TARGET}" --show-bin-path)/AskAside"
}

echo "==> Building arm64 slice"
ARM_BIN="$(build_slice arm64)"
echo "==> Building x86_64 slice"
X86_BIN="$(build_slice x86_64)"

echo "==> Assembling $APP (universal)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP/Contents/MacOS/AskAside"
cp Info.plist "$APP/Contents/Info.plist"

# Prefer the stable self-signed identity (see setup-dev-cert.sh) so rebuilds keep the
# Accessibility grant. Fall back to ad-hoc if it isn't set up.
SIGN_ID="AskAside Dev"
# A self-signed dev cert is untrusted, so it appears under `find-identity` (all) but NOT
# under `find-identity -p codesigning` (trusted only). codesign uses it fine.
if security find-identity 2>/dev/null | grep -q "$SIGN_ID"; then
  echo "==> Signing with stable identity '$SIGN_ID'"
  codesign --force --deep --sign "$SIGN_ID" "$APP"
else
  echo "==> Signing (ad-hoc; run ./setup-dev-cert.sh once to stop re-granting Accessibility)"
  codesign --force --deep --sign - "$APP"
fi

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/AskAside"))"
echo "Launch with:  open \"$PWD/$APP\""
