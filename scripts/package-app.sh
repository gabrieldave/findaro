#!/usr/bin/env bash
# Empaqueta Findaro (.app), instala en /Applications y VERIFICA identidad real.
# No borra Ordena.app ni sus datos (conviven hasta que confirmes Findaro).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRODUCT_NAME="Findaro"
# Bundle ID propio: si se reutiliza app.ordena.files, Dock/Launch Services
# confunden Findaro con Ordena.app (mismo ID = misma app para macOS).
BUNDLE_ID="app.findaro.files"
VERSION="0.1.106"
BUILD="110"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

swift build -c release --product Orden
# Conservar AppIcon.icns instalado/aprobado: no regenerar hasta que dirección entregue PNG final.
if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "WARN: falta Resources/AppIcon.icns — generando fallback temporal" >&2
  swift "$ROOT/scripts/generate-findaro-icon.swift" "$ROOT/Resources"
fi
BIN="$(swift build -c release --show-bin-path)/Orden"

APP_DIR="$ROOT/dist/${PRODUCT_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# El producto SPM conserva el nombre interno Orden; el bundle comercial se llama Findaro.
cp "$BIN" "$APP_DIR/Contents/MacOS/${PRODUCT_NAME}"
chmod +x "$APP_DIR/Contents/MacOS/${PRODUCT_NAME}"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "ERROR: falta Resources/AppIcon.icns" >&2
  exit 1
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

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
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Findaro usa reconocimiento de voz local para el asistente push-to-talk.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Findaro usa el micrófono solo mientras mantienes el botón de dictado.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
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

ENTITLEMENTS="$ROOT/Resources/Ordena.entitlements"
SIGN_ID="${ORDENA_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
if [[ -n "$SIGN_ID" ]]; then
  echo "==> Firmando con: $SIGN_ID"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_ID" "$APP_DIR"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
else
  echo "==> Sin Developer ID — firma adhoc (Gatekeeper pedirá clic derecho → Abrir)"
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

# No borramos Ordena.app (convivencia). Solo limpia alias viejos de Escritorio.
rm -rf "$HOME/Desktop/Orden.app" "$HOME/Desktop/Orden" 2>/dev/null || true

verify_bundle() {
  local app="$1"
  local plist="$app/Contents/Info.plist"
  local exe="$app/Contents/MacOS/${PRODUCT_NAME}"
  local icns="$app/Contents/Resources/AppIcon.icns"
  local fail=0

  echo "==> Verificación de $app"
  for key in CFBundleName CFBundleDisplayName CFBundleIdentifier CFBundleIconFile CFBundleExecutable CFBundleShortVersionString; do
    local val
    val="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || echo MISSING)"
    echo "  $key=$val"
  done

  local name display ident icon exeName
  name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$plist")"
  display="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$plist")"
  ident="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
  icon="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist")"
  exeName="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"

  [[ "$name" == "$PRODUCT_NAME" ]] || { echo "  FAIL CFBundleName"; fail=1; }
  [[ "$display" == "$PRODUCT_NAME" ]] || { echo "  FAIL CFBundleDisplayName"; fail=1; }
  [[ "$ident" == "$BUNDLE_ID" ]] || { echo "  FAIL CFBundleIdentifier (got $ident)"; fail=1; }
  [[ "$icon" == "AppIcon" ]] || { echo "  FAIL CFBundleIconFile"; fail=1; }
  [[ "$exeName" == "$PRODUCT_NAME" ]] || { echo "  FAIL CFBundleExecutable"; fail=1; }
  [[ -x "$exe" ]] || { echo "  FAIL executable missing: $exe"; fail=1; }
  [[ -f "$icns" ]] || { echo "  FAIL icon missing: $icns"; fail=1; }

  if [[ -f "$icns" && -f "$ROOT/Resources/AppIcon.icns" ]]; then
    local h1 h2
    h1="$(md5 -q "$icns")"
    h2="$(md5 -q "$ROOT/Resources/AppIcon.icns")"
    echo "  icon_md5=$h1"
    [[ "$h1" == "$h2" ]] || { echo "  FAIL icon MD5 mismatch vs Resources/AppIcon.icns"; fail=1; }
  fi

  if [[ -d "/Applications/Ordena.app" ]]; then
    local old_id
    old_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/Ordena.app/Contents/Info.plist 2>/dev/null || true)"
    echo "  note: Ordena.app sigue instalada (id=$old_id) — no se elimina"
    if [[ "$old_id" == "$ident" ]]; then
      echo "  FAIL: Findaro e Ordena comparten el mismo CFBundleIdentifier"
      fail=1
    fi
  fi

  return "$fail"
}

verify_bundle "$APP_DIR"

if [[ "${FINDARO_SKIP_INSTALL:-0}" == "1" ]]; then
  echo "APP=$APP_DIR"
  echo "INSTALLED=(omitido FINDARO_SKIP_INSTALL=1)"
  echo "BUNDLE_ID=$BUNDLE_ID"
  exit 0
fi

INSTALLED=""
if rm -rf "/Applications/${PRODUCT_NAME}.app" 2>/dev/null \
  && cp -R "$APP_DIR" "/Applications/${PRODUCT_NAME}.app" 2>/dev/null; then
  INSTALLED="/Applications/${PRODUCT_NAME}.app"
else
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/${PRODUCT_NAME}.app"
  cp -R "$APP_DIR" "$HOME/Applications/${PRODUCT_NAME}.app"
  INSTALLED="$HOME/Applications/${PRODUCT_NAME}.app"
fi

# Fuerza a Launch Services a re-leer nombre/icono del bundle nuevo.
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$INSTALLED" >/dev/null 2>&1 || true
fi
# Touch para invalidar caché de iconos del Finder.
touch "$INSTALLED"

verify_bundle "$INSTALLED"

# Reinicia solo Findaro (no Ordena).
if pgrep -x "${PRODUCT_NAME}" >/dev/null 2>&1; then
  pkill -x "${PRODUCT_NAME}" >/dev/null 2>&1 || true
  sleep 0.5
fi

echo "APP=$APP_DIR"
echo "INSTALLED=$INSTALLED"
echo "EXECUTABLE=$INSTALLED/Contents/MacOS/${PRODUCT_NAME}"
echo "BUNDLE_ID=$BUNDLE_ID"
echo "TIP=Launchpad / Spotlight (⌘Space → ${PRODUCT_NAME}) / arrastra a Dock"
echo "NOTE=Ordena.app se conserva. Quita el tile viejo del Dock si aún dice Ordena y arrastra Findaro.app."
