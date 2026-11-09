#!/usr/bin/env bash
# Empaqueta Findaro BETA privado para testers.
# NO instala ni sustituye /Applications. NO publica feed. NO ejecuta publish-update.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep -E '^VERSION=' scripts/package-app.sh | head -1 | cut -d= -f2 | tr -d '"')"
BUILD="$(grep -E '^BUILD=' scripts/package-app.sh | head -1 | cut -d= -f2 | tr -d '"')"
ARCH="$(uname -m)"
PRODUCT_NAME="Findaro"
BUNDLE_ID="app.findaro.files"
DMG_NAME="${PRODUCT_NAME}-${VERSION}-${ARCH}-beta.dmg"
OUT_DIR="$ROOT/dist/beta"
APP_DIR="$OUT_DIR/${PRODUCT_NAME}.app"
OUT_DMG="$OUT_DIR/${DMG_NAME}"
INSTRUCTIONS="$OUT_DIR/INSTRUCCIONES-BETA.txt"
ENTITLEMENTS="$ROOT/Resources/Ordena.entitlements"

mkdir -p "$OUT_DIR"
rm -rf "$APP_DIR" "$OUT_DMG"

echo "==> Compilando Release…"
swift build -c release --product Orden
BIN="$(swift build -c release --show-bin-path)/Orden"

[[ -f "$ROOT/Resources/AppIcon.icns" ]] || {
  echo "ERROR: falta Resources/AppIcon.icns (arte aprobado). No regenerar." >&2
  exit 1
}

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/${PRODUCT_NAME}"
chmod +x "$APP_DIR/Contents/MacOS/${PRODUCT_NAME}"
cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>es</string>
  <key>CFBundleExecutable</key><string>${PRODUCT_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>${PRODUCT_NAME}</string>
  <key>CFBundleDisplayName</key><string>${PRODUCT_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Findaro usa reconocimiento de voz local para el asistente push-to-talk.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Findaro usa el micrófono solo mientras mantienes el botón de dictado.</string>
  <key>NSAppleEventsUsageDescription</key><string>Findaro asks Finder to empty the Trash and restore items from it.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
</dict>
</plist>
PLIST

SIGN_STATUS="adhoc"
SIGN_ID="${ORDENA_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi

if [[ -n "$SIGN_ID" ]]; then
  echo "==> Firmando Developer ID: $SIGN_ID"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_ID" "$APP_DIR"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
  SIGN_STATUS="developer-id"
else
  echo "WARN: No hay certificado «Developer ID Application»."
  echo "WARN: Solo existe (si acaso) Apple Development — NO sirve para distribuir a terceros."
  echo "WARN: Se firma ad hoc. Gatekeeper pedirá clic derecho → Abrir."
  echo "WARN: NOTARIZACIÓN: NO disponible sin Developer ID + credenciales notarytool."
  codesign --force --deep --sign - "$APP_DIR"
  SIGN_STATUS="adhoc-not-notarized"
fi

# Veridad de identidad
IDENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")"
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
[[ "$IDENT" == "$BUNDLE_ID" ]] || { echo "FAIL Bundle ID $IDENT"; exit 1; }
[[ "$VER" == "$VERSION" ]] || { echo "FAIL version $VER"; exit 1; }
ICON_H1="$(md5 -q "$APP_DIR/Contents/Resources/AppIcon.icns")"
ICON_H2="$(md5 -q "$ROOT/Resources/AppIcon.icns")"
[[ "$ICON_H1" == "$ICON_H2" ]] || { echo "FAIL icon MD5"; exit 1; }

STAGE="$OUT_DIR/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/${PRODUCT_NAME}.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Léeme-BETA.txt" <<EOF
FINDARO ${VERSION} (build ${BUILD}) — BETA PRIVADA

Instalación:
1. Arrastra Findaro.app a Aplicaciones (o a ~/Applications).
2. Si macOS bloquea: clic derecho en Findaro → Abrir → Abrir.
3. Spotlight: ⌘Espacio → Findaro

Firma: ${SIGN_STATUS}
Notarización: NO (esta build beta no está notarizada salvo que el log diga lo contrario).
EOF

RW="$OUT_DIR/rw.dmg"
rm -f "$RW" "$OUT_DMG"
hdiutil create -volname "Findaro ${VERSION} beta" -srcfolder "$STAGE" -ov -format UDRW "$RW" >/dev/null
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" >/dev/null
rm -f "$RW"
rm -rf "$STAGE"

SHA256="$(shasum -a 256 "$OUT_DMG" | awk '{print $1}')"
echo "$SHA256  ${DMG_NAME}" > "$OUT_DIR/${DMG_NAME}.sha256"

cat > "$INSTRUCTIONS" <<EOF
FINDARO BETA ${VERSION} (build ${BUILD}) — instrucciones para testers
================================================================

Archivo: ${DMG_NAME}
SHA-256: ${SHA256}
Bundle ID: ${BUNDLE_ID}
macOS mínimo: 15 · Apple Silicon (arm64)
Firma: ${SIGN_STATUS}
Notarización: NO

Cómo instalar
1. Envía solo el .dmg (y opcionalmente el .sha256).
2. El tester abre el DMG y arrastra Findaro.app a Aplicaciones.
3. Si aparece «app dañada / no se puede abrir»:
   clic derecho → Abrir → Abrir (solo la primera vez).
4. NO borres Ordena.app si la tienes: pueden coexistir.

Qué probar
- Icono en sidebar (FINDARO + marca visual).
- Doble panel, bandeja, Smart Merge.
- Actualizaciones: en beta privada el feed de producción puede no aplicar.

Verificar integridad
  shasum -a 256 -c ${DMG_NAME}.sha256
EOF

# Copia útil al Escritorio (no toca /Applications)
cp -f "$OUT_DMG" "$HOME/Desktop/${DMG_NAME}"
cp -f "$OUT_DIR/${DMG_NAME}.sha256" "$HOME/Desktop/${DMG_NAME}.sha256"
cp -f "$INSTRUCTIONS" "$HOME/Desktop/FINDARO-BETA-INSTRUCCIONES.txt"

echo "APP=$APP_DIR"
echo "DMG=$OUT_DMG"
echo "DESKTOP=$HOME/Desktop/${DMG_NAME}"
echo "SHA256=$SHA256"
echo "SIGN_STATUS=$SIGN_STATUS"
echo "NOTARIZED=no"
echo "INSTALLED_LOCAL=no (este script no toca /Applications)"
