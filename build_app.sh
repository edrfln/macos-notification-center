#!/bin/bash
# Builds DynamicNotch.app.
#
# Environment (all optional):
#   VERSION=1.2.0           CFBundleShortVersionString (default: latest git tag without "v", else 1.0)
#   BUILD_NUMBER=42         CFBundleVersion (default: git commit count)
#   UNIVERSAL=1             Build a universal binary (Apple Silicon + Intel) for distribution
#   CODESIGN_IDENTITY=name  Sign with this keychain identity (e.g. a self-signed certificate) instead of ad-hoc.
#                           A stable identity lets macOS keep the Accessibility grant across updates.
#   CODESIGN_KEYCHAIN=path  Keychain holding CODESIGN_IDENTITY (used by CI; defaults to the login keychain search list)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

BUILD_FLAGS=(-c release)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "Building DynamicNotch $VERSION ($BUILD_NUMBER) in release mode..."
swift build "${BUILD_FLAGS[@]}"
BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/DynamicNotch"

APP_DIR="DynamicNotch.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Creating bundle structure at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/scripts"

cp "$BIN_PATH" "$MACOS_DIR/DynamicNotch"

# Ship the shell / Claude Code integrations inside the app so downloads don't need a clone.
cp scripts/*.sh "$RESOURCES_DIR/scripts/"
chmod +x "$RESOURCES_DIR/scripts/"*.sh

cat << EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DynamicNotch</string>
    <key>CFBundleIdentifier</key>
    <string>com.dynamicnotch.DynamicNotch</string>
    <key>CFBundleName</key>
    <string>Dynamic Notch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Dynamic Notch controls playback and reads track artwork from Music and Spotify.</string>
</dict>
</plist>
EOF

echo "Signing with identity: $([[ "$CODESIGN_IDENTITY" == "-" ]] && echo "ad-hoc" || echo "$CODESIGN_IDENTITY")"
SIGN_FLAGS=(--force --sign "$CODESIGN_IDENTITY" --timestamp=none)
if [[ -n "${CODESIGN_KEYCHAIN:-}" ]]; then
    SIGN_FLAGS+=(--keychain "$CODESIGN_KEYCHAIN")
fi
codesign "${SIGN_FLAGS[@]}" "$APP_DIR"
codesign --verify --strict "$APP_DIR"

echo "DynamicNotch.app bundle created successfully!"
echo "Architectures: $(lipo -archs "$MACOS_DIR/DynamicNotch")"
echo "Run with: open DynamicNotch.app"
