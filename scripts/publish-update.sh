#!/usr/bin/env bash
# Arma DMG Findaro (+ puente Ordena para clientes 0.1.74) y publica el feed.
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
# Default: VPS ecosistema (Host «vps» a veces no resuelve en DNS local).
HOST="${FINDARO_SSH_HOST:-${ORDENA_SSH_HOST:-root@147.93.181.3}}"
REMOTE_DIR="${FINDARO_REMOTE_DIR:-${ORDENA_REMOTE_DIR:-/var/www/ordena}}"
PUBLIC_BASE="${FINDARO_PUBLIC_BASE:-https://ordena.iareal.net}"

echo "==> Empaquetando ${PRODUCT_NAME}.app…"
"$ROOT/scripts/package-app.sh"

FINDARO_APP="$ROOT/dist/${PRODUCT_NAME}.app"
[[ -d "$FINDARO_APP" ]] || { echo "No está $FINDARO_APP"; exit 1; }

# Puente: misma build con nombre Ordena.app + bundle id viejo para que
# el actualizador de Ordena 0.1.74 (busca Ordena.app) pueda instalar sola.
LEGACY_APP="$ROOT/dist/${LEGACY_NAME}.app"
rm -rf "$LEGACY_APP"
ditto "$FINDARO_APP" "$LEGACY_APP"
# Renombrar ejecutable al nombre del bundle legacy
if [[ -f "$LEGACY_APP/Contents/MacOS/${PRODUCT_NAME}" ]]; then
  mv "$LEGACY_APP/Contents/MacOS/${PRODUCT_NAME}" "$LEGACY_APP/Contents/MacOS/${LEGACY_NAME}"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${LEGACY_NAME}" "$LEGACY_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.ordena.files" "$LEGACY_APP/Contents/Info.plist"
# DisplayName Findaro para que vea el branding nuevo en el Dock/menú
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${PRODUCT_NAME}" "$LEGACY_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleName string ${PRODUCT_NAME}" "$LEGACY_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${PRODUCT_NAME}" "$LEGACY_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ${PRODUCT_NAME}" "$LEGACY_APP/Contents/Info.plist"

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
  cat > "$stage/Léeme.txt" <<EOF
${product} ${VERSION}

Instalación:
1. Arrastra ${product}.app a Aplicaciones.
2. Abre desde Spotlight (⌘Espacio).
EOF
  hdiutil create -volname "${product} ${VERSION}-${ARCH}" -srcfolder "$stage" -ov -format UDRW "$rw" >/dev/null
  hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$out" >/dev/null
  rm -f "$rw"
  rm -rf "$stage"
  echo "$out"
}

echo "==> DMG Findaro (instalación limpia)…"
FINDARO_DMG="$(make_dmg "$FINDARO_APP" "$PRODUCT_NAME" "$DMG_NAME")"
echo "==> DMG Ordena puente (auto-update clientes viejos)…"
LEGACY_DMG="$(make_dmg "$LEGACY_APP" "$LEGACY_NAME" "$LEGACY_DMG_NAME")"

cp -f "$FINDARO_DMG" "$HOME/Desktop/${DMG_NAME}"
cp -f "$LEGACY_DMG" "$HOME/Desktop/${LEGACY_DMG_NAME}"

SHA256="$(shasum -a 256 "$LEGACY_DMG" | awk '{print $1}')"
FINDARO_SHA="$(shasum -a 256 "$FINDARO_DMG" | awk '{print $1}')"

echo "==> Publicando en ${HOST}:${REMOTE_DIR}…"
scp "$FINDARO_DMG" "${HOST}:${REMOTE_DIR}/downloads/${DMG_NAME}"
scp "$FINDARO_DMG" "${HOST}:${REMOTE_DIR}/downloads/${PRODUCT_NAME}-latest.dmg"
scp "$LEGACY_DMG" "${HOST}:${REMOTE_DIR}/downloads/${LEGACY_DMG_NAME}"
scp "$LEGACY_DMG" "${HOST}:${REMOTE_DIR}/downloads/${LEGACY_NAME}-latest.dmg"

# latest.json apunta al puente Ordena: así Ordena 0.1.74 muestra la ventanita
# Instalar/Después y reemplaza /Applications/Ordena.app con branding Findaro.
ssh "$HOST" "cat > '${REMOTE_DIR}/downloads/latest.json' <<EOF
{
  \"version\": \"${VERSION}\",
  \"tag\": \"v${VERSION}\",
  \"dmg_url\": \"${PUBLIC_BASE}/downloads/${LEGACY_DMG_NAME}\",
  \"notes_url\": \"${PUBLIC_BASE}/\",
  \"sha256\": \"${SHA256}\",
  \"findaro_dmg_url\": \"${PUBLIC_BASE}/downloads/${DMG_NAME}\",
  \"findaro_sha256\": \"${FINDARO_SHA}\"
}
EOF
cat > '${REMOTE_DIR}/index.html' <<EOF
<!doctype html>
<html lang=\"es\"><head>
<meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
<title>Findaro</title>
<style>
body{margin:0;font:16px/1.5 system-ui;background:#0B1220;color:#E8EEF7;min-height:100vh;display:grid;place-items:center}
main{max-width:28rem;padding:2rem;text-align:center}
h1{font-size:2.4rem;margin:0 0 .4rem;letter-spacing:-.03em}
p{color:#8B9BB4}
a{display:inline-block;margin-top:1rem;padding:.85rem 1.4rem;border-radius:12px;background:#2563EB;color:#fff;font-weight:700;text-decoration:none}
small{display:block;margin-top:1rem;color:#8B9BB4}
</style></head><body><main>
<h1>FINDARO</h1>
<p>Explorador de archivos para Mac. Apple Silicon.</p>
<a href=\"/downloads/${DMG_NAME}\">Descargar Findaro ${VERSION}</a>
<small>macOS 15+ · arm64 · actualizaciones automáticas</small>
</main></body></html>
EOF"

echo "Publicado v${VERSION}"
echo "  bridge(Ordena auto-update)=$LEGACY_DMG_NAME sha256=${SHA256}"
echo "  findaro=$DMG_NAME sha256=${FINDARO_SHA}"
echo "  desktop=$HOME/Desktop/${DMG_NAME}"
curl -sS "${PUBLIC_BASE}/downloads/latest.json"
echo
