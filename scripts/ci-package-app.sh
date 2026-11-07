#!/usr/bin/env bash
# Empaqueta Findaro.app en dist/ para CI (sin instalar, sin notarizar, sin regenerar icono).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRODUCT_NAME="Findaro"
BUNDLE_ID="app.findaro.files"
VERSION="$(grep -E '^VERSION=' scripts/package-app.sh | head -1 | cut -d= -f2 | tr -d '"')"
BUILD="$(grep -E '^BUILD=' scripts/package-app.sh | head -1 | cut -d= -f2 | tr -d '"')"

test -s Resources/AppIcon.icns
swift build --product Orden
BIN="$(swift build --product Orden --show-bin-path)/Orden"

APP_DIR="$ROOT/dist/${PRODUCT_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/${PRODUCT_NAME}"
chmod +x "$APP_DIR/Contents/MacOS/${PRODUCT_NAME}"
cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD}</string>
</dict>
</plist>
PLIST

test -x "$APP_DIR/Contents/MacOS/${PRODUCT_NAME}"
IDENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")"
[[ "$IDENT" == "$BUNDLE_ID" ]]
echo "PACKAGED=$APP_DIR"
echo "VERSION=$VERSION"
echo "BUNDLE_ID=$BUNDLE_ID"
