#!/usr/bin/env bash
# Empaqueta Orden como app real (.app) — visible en Dock y Escritorio.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --product Orden
BIN="$(swift build -c release --show-bin-path)/Orden"

APP_DIR="$ROOT/dist/Orden.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/Orden"
chmod +x "$APP_DIR/Contents/MacOS/Orden"

# Icono Dock
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>es</string>
  <key>CFBundleExecutable</key>
  <string>Orden</string>
  <key>CFBundleIdentifier</key>
  <string>app.orden.files</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Orden</string>
  <key>CFBundleDisplayName</key>
  <string>Orden</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>3</string>
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
</dict>
</plist>
PLIST

# Icono simple (SF Symbol → icns vía iconutil si hay sips; si no, sin icono)
# Firma ad-hoc (para vender/notarizar hace falta Developer ID + notarization)
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

# Instalar en Aplicaciones del sistema; si no hay permiso, en ~/Applications.
# No dejamos copia en el Escritorio (no ensucia).
rm -rf "$HOME/Desktop/Orden" "$HOME/Desktop/Orden.app"

INSTALLED=""
if rm -rf /Applications/Orden.app 2>/dev/null && cp -R "$APP_DIR" /Applications/Orden.app 2>/dev/null; then
  INSTALLED="/Applications/Orden.app"
else
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Orden.app"
  cp -R "$APP_DIR" "$HOME/Applications/Orden.app"
  INSTALLED="$HOME/Applications/Orden.app"
fi

echo "APP=$APP_DIR"
echo "INSTALLED=$INSTALLED"
echo "TIP=Launchpad / Spotlight (⌘Space → Orden) / arrastra a Dock para acceso fijo"
