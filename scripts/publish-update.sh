#!/usr/bin/env bash
# Arma el DMG Findaro y lo publica en el host de actualizaciones.
# NO ejecutar sin autorización explícita del director.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep -E '^VERSION=' scripts/package-app.sh | head -1 | cut -d= -f2 | tr -d '"')"
ARCH="$(uname -m)"
PRODUCT_NAME="Findaro"
DMG_NAME="${PRODUCT_NAME}-${VERSION}-${ARCH}.dmg"
# Default: VPS ecosistema (Host «vps» a veces no resuelve en DNS local).
HOST="${FINDARO_SSH_HOST:-${ORDENA_SSH_HOST:-root@147.93.181.3}}"
REMOTE_DIR="${FINDARO_REMOTE_DIR:-${ORDENA_REMOTE_DIR:-/var/www/ordena}}"
PUBLIC_BASE="${FINDARO_PUBLIC_BASE:-https://ordena.iareal.net}"

"$ROOT/scripts/make-dmg.sh"
DMG="$ROOT/dist/${DMG_NAME}"
[[ -f "$DMG" ]] || { echo "No está $DMG"; exit 1; }

SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"

scp "$DMG" "${HOST}:${REMOTE_DIR}/downloads/${DMG_NAME}"
scp "$DMG" "${HOST}:${REMOTE_DIR}/downloads/${PRODUCT_NAME}-latest.dmg"

ssh "$HOST" "cat > '${REMOTE_DIR}/downloads/latest.json' <<EOF
{
  \"version\": \"${VERSION}\",
  \"tag\": \"v${VERSION}\",
  \"dmg_url\": \"${PUBLIC_BASE}/downloads/${DMG_NAME}\",
  \"notes_url\": \"${PUBLIC_BASE}/\",
  \"sha256\": \"${SHA256}\"
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

echo "Publicado v${VERSION} sha256=${SHA256}"
curl -sS "${PUBLIC_BASE}/downloads/latest.json"
echo
