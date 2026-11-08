#!/usr/bin/env bash
# Arma DMG Findaro (+ puente Ordena) y publica el feed.
# REQUIERE Developer ID Application válido. NO publica con firma ad hoc.
# NO ejecutar sin autorización explícita del director.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep -E '^VERSION=' scripts/package-app.sh | head -1 | cut -d= -f2 | tr -d '"')"
ARCH="$(uname -m)"
PRODUCT_NAME="Findaro"
LEGACY_NAME="Ordena"
DMG_NAME="${PRODUCT_NAME}-${VERSION}-${ARCH}.dmg"
LEGACY_DMG_NAME="${LEGACY_NAME}-${VERSION}-${ARCH}.dmg"
HOST="${FINDARO_SSH_HOST:-${ORDENA_SSH_HOST:-vps}}"
REMOTE_DIR="${FINDARO_REMOTE_DIR:-${ORDENA_REMOTE_DIR:-/var/www/ordena}}"
PUBLIC_BASE="${FINDARO_PUBLIC_BASE:-https://ordena.iareal.net}"
ENTITLEMENTS="$ROOT/Resources/Ordena.entitlements"

SIGN_ID="${ORDENA_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
if [[ -z "$SIGN_ID" ]]; then
  cat >&2 <<EOF
ERROR: No hay certificado «Developer ID Application».
Este Mac solo tiene identidades de desarrollo (p. ej. Apple Development),
que NO sirven para distribuir ni notarizar.

Acción: instala un Developer ID Application en el llavero (o define
ORDENA_SIGN_IDENTITY) y credenciales de notarytool (APPLE_ID,
APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID).

Abortado: no se publicará ningún paquete con firma inválida o ad hoc.
EOF
  exit 1
fi

echo "==> Identidad de distribución: $SIGN_ID"

sign_bundle() {
  local app="$1"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_ID" "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
  spctl --assess --type execute --verbose "$app" 2>&1 || {
    echo "WARN: spctl assess falló (puede requerir notarización previa del ticket)." >&2
  }
}

echo "==> Empaquetando ${PRODUCT_NAME}.app…"
FINDARO_SKIP_INSTALL=1 "$ROOT/scripts/package-app.sh"
FINDARO_APP="$ROOT/dist/${PRODUCT_NAME}.app"
[[ -d "$FINDARO_APP" ]] || { echo "No está $FINDARO_APP"; exit 1; }
sign_bundle "$FINDARO_APP"

# Puente legacy: misma build, Bundle ID Ordena, re-firmado tras mutar Info.plist.
LEGACY_APP="$ROOT/dist/${LEGACY_NAME}.app"
rm -rf "$LEGACY_APP"
ditto "$FINDARO_APP" "$LEGACY_APP"
if [[ -f "$LEGACY_APP/Contents/MacOS/${PRODUCT_NAME}" ]]; then
  mv "$LEGACY_APP/Contents/MacOS/${PRODUCT_NAME}" "$LEGACY_APP/Contents/MacOS/${LEGACY_NAME}"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${LEGACY_NAME}" "$LEGACY_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.ordena.files" "$LEGACY_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${PRODUCT_NAME}" "$LEGACY_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleName string ${PRODUCT_NAME}" "$LEGACY_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${PRODUCT_NAME}" "$LEGACY_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ${PRODUCT_NAME}" "$LEGACY_APP/Contents/Info.plist"
echo "==> Re-firmando puente Ordena tras mutar identidad…"
sign_bundle "$LEGACY_APP"

make_dmg() {
  local app_src="$1"
  local product="$2"
  local out_name="$3"
  local stage="$ROOT/dist/dmg-stage-${product}"
  local rw="$ROOT/dist/${product}-rw.dmg"
  local out="$ROOT/dist/${out_name}"
  rm -rf "$stage" "$rw" "$out"
  mkdir -p "$stage"
  cp -R "$app_src" "$stage/${product}.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "${product} ${VERSION}-${ARCH}" -srcfolder "$stage" -ov -format UDRW "$rw" >/dev/null
  hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$out" >/dev/null
  rm -f "$rw"
  rm -rf "$stage"
  echo "$out"
}

FINDARO_DMG="$(make_dmg "$FINDARO_APP" "$PRODUCT_NAME" "$DMG_NAME")"
LEGACY_DMG="$(make_dmg "$LEGACY_APP" "$LEGACY_NAME" "$LEGACY_DMG_NAME")"

# Firmar DMGs (Developer ID Installer no siempre aplica; codesign del dmg ayuda al notary)
codesign --force --sign "$SIGN_ID" "$FINDARO_DMG" || true
codesign --force --sign "$SIGN_ID" "$LEGACY_DMG" || true

echo "==> Notarizando ambos DMG…"
"$ROOT/scripts/notarize-dmg.sh" "$FINDARO_DMG"
"$ROOT/scripts/notarize-dmg.sh" "$LEGACY_DMG"

SHA256="$(shasum -a 256 "$LEGACY_DMG" | awk '{print $1}')"
FINDARO_SHA="$(shasum -a 256 "$FINDARO_DMG" | awk '{print $1}')"

echo "==> Publicando en ${HOST}:${REMOTE_DIR}…"
scp "$FINDARO_DMG" "${HOST}:${REMOTE_DIR}/downloads/${DMG_NAME}"
scp "$FINDARO_DMG" "${HOST}:${REMOTE_DIR}/downloads/${PRODUCT_NAME}-latest.dmg"
scp "$LEGACY_DMG" "${HOST}:${REMOTE_DIR}/downloads/${LEGACY_DMG_NAME}"
scp "$LEGACY_DMG" "${HOST}:${REMOTE_DIR}/downloads/${LEGACY_NAME}-latest.dmg"

ssh "$HOST" "cat > '${REMOTE_DIR}/downloads/latest.json'" <<EOF
{
  "version": "${VERSION}",
  "tag": "v${VERSION}",
  "dmg_url": "${PUBLIC_BASE}/downloads/${LEGACY_DMG_NAME}",
  "notes_url": "${PUBLIC_BASE}/",
  "sha256": "${SHA256}",
  "findaro_dmg_url": "${PUBLIC_BASE}/downloads/${DMG_NAME}",
  "findaro_sha256": "${FINDARO_SHA}"
}
EOF

ssh "$HOST" "cat > '${REMOTE_DIR}/index.html'" <<'EOF'
<!doctype html>
<html lang="es"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="0;url=https://findaro.iareal.net/">
<title>FINDARO</title>
</head><body style="font:16px system-ui;background:#0B1220;color:#E8EEF7;display:grid;place-items:center;min-height:100vh">
<main style="text-align:center">
<h1>FINDARO</h1>
<p>La descarga ahora es por licencia oficial.</p>
<a style="color:#fff;background:#2563EB;padding:.85rem 1.4rem;border-radius:12px;text-decoration:none;font-weight:700" href="https://findaro.iareal.net/comprar">Comprar / Descargar en findaro.iareal.net</a>
</main></body></html>
EOF

echo "Publicado v${VERSION}"
curl -sS "${PUBLIC_BASE}/downloads/latest.json"
echo
