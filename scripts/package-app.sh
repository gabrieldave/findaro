#!/usr/bin/env bash
# Empaqueta Ordena (.app) e instala en /Applications.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRODUCT_NAME="Ordena"
BUNDLE_ID="app.ordena.files"
VERSION="0.1.18"
BUILD="21"

swift build -c release --product Orden
BIN="$(swift build -c release --show-bin-path)/Orden"

APP_DIR="$ROOT/dist/${PRODUCT_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# El binario SPM sigue llamándose Orden; en el bundle se nombra Ordena.
cp "$BIN" "$APP_DIR/Contents/MacOS/${PRODUCT_NAME}"
chmod +x "$APP_DIR/Contents/MacOS/${PRODUCT_NAME}"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>es</string>
  <key>CFBundleExecutable</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Folder</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.folder</string>
        <string>public.directory</string>
      </array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Files</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.item</string>
        <string>public.data</string>
      </array>
    </dict>
  </array>
  <key>UTImportedTypeDeclarations</key>
  <array/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

# Limpia nombres viejos y Escritorio
rm -rf "$HOME/Desktop/Orden.app" "$HOME/Desktop/Ordena.app" \
       "$HOME/Desktop/Orden" "$HOME/Applications/Orden.app"

INSTALLED=""
if rm -rf "/Applications/Orden.app" "/Applications/${PRODUCT_NAME}.app" 2>/dev/null \
  && cp -R "$APP_DIR" "/Applications/${PRODUCT_NAME}.app" 2>/dev/null; then
  INSTALLED="/Applications/${PRODUCT_NAME}.app"
else
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Orden.app" "$HOME/Applications/${PRODUCT_NAME}.app"
  cp -R "$APP_DIR" "$HOME/Applications/${PRODUCT_NAME}.app"
  INSTALLED="$HOME/Applications/${PRODUCT_NAME}.app"
fi

# Si Ordena está abierta, reinicia para cargar el binario nuevo (si no, sigue el viejo en memoria).
if pgrep -x "${PRODUCT_NAME}" >/dev/null 2>&1; then
  pkill -x "${PRODUCT_NAME}" >/dev/null 2>&1 || true
  sleep 0.4
  open -a "${PRODUCT_NAME}" >/dev/null 2>&1 || true
fi

echo "APP=$APP_DIR"
echo "INSTALLED=$INSTALLED"
echo "TIP=Launchpad / Spotlight (⌘Space → ${PRODUCT_NAME}) / arrastra a Dock"
