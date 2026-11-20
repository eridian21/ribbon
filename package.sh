#!/bin/bash
# Builds a universal (Apple Silicon + Intel) Ribbon.app and packages it as
# dist/Ribbon-<version>.dmg, with the usual "drag Ribbon into Applications" layout.
# The version comes from CFBundleShortVersionString in Resources/Info.plist.
#
# Signing: uses CODESIGN_IDENTITY, default "Ribbon Dev". Releases should always be signed
# with the same certificate so users keep their Accessibility permission across updates.
# The app is not notarized (that needs a paid Apple Developer ID), so on first launch
# users have to approve it in System Settings → Privacy & Security → Open Anyway.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
IDENTITY="${CODESIGN_IDENTITY:-Ribbon Dev}"
if [[ "$IDENTITY" != "-" ]] && ! security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "error: signing identity \"$IDENTITY\" not found. Set CODESIGN_IDENTITY (or \"-\" for ad-hoc)." >&2
    exit 1
fi

echo "==> Building Ribbon $VERSION (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BINARY=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Ribbon

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Ribbon.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Ribbon"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
ln -s /Applications "$STAGING/Applications"

mkdir -p dist
DMG="dist/Ribbon-$VERSION.dmg"
rm -f "$DMG"
echo "==> Creating $DMG"
hdiutil create -quiet -volname "Ribbon $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1 | xargs))"
lipo -archs "$APP/Contents/MacOS/Ribbon" | sed 's/^/    architectures: /'
