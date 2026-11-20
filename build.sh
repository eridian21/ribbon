#!/bin/bash
# Builds build/Ribbon.app, signed with the "Ribbon Dev" self-signed certificate so the
# Accessibility grant survives rebuilds. Override with CODESIGN_IDENTITY=... ./build.sh.
# If the certificate is missing, falls back to ad-hoc signing ("-"), which changes every
# build and means re-granting Accessibility after each rebuild.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${CODESIGN_IDENTITY:-Ribbon Dev}"
if [[ "$IDENTITY" != "-" ]] && ! security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "warning: signing identity \"$IDENTITY\" not found in your keychain; using ad-hoc signing" >&2
    IDENTITY="-"
fi

swift build -c release

APP=build/Ribbon.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Ribbon "$APP/Contents/MacOS/Ribbon"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$IDENTITY" "$APP"

echo "Built $APP (signed with: $IDENTITY)"
