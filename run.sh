#!/bin/bash
# Build and run the Kanbango app as a proper .app bundle
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Kanbango"

# Kill existing instance
echo "Killing existing $APP_NAME..."
pkill -9 "$APP_NAME" 2>/dev/null || true
sleep 0.5

# Build
swift build -c release

# Generate .app bundle at project root (not buried in .build/)
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp ".build/release/$APP_NAME" "$APP_MACOS/$APP_NAME"
cp -R "$SCRIPT_DIR/Sources/Kanbango/Assets.xcassets" "$APP_RESOURCES/"
cp "$SCRIPT_DIR/Sources/Kanbango/AppIcon.icns" "$APP_RESOURCES/"

# Info.plist
cat > "$APP_CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Kanbango</string>
    <key>CFBundleDisplayName</key>
    <string>Kanbango</string>
    <key>CFBundleIdentifier</key>
    <string>com.kanbango.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Kanbango</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
</dict>
</plist>
EOF

# Ad-hoc sign
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "Launching $APP_NAME.app..."
open "$APP_BUNDLE"
