#!/usr/bin/env bash
# Arma DMG Findaro (+ puente Ordena) y publica el feed.
# REQUIERE Developer ID Application válido. NO publica con firma ad hoc.
# NO ejecutar sin autorización explícita del director.
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "$0")/.." && pwd))"
ROOT="$REPO_ROOT"
cd "$ROOT"

get_secret_val() {
  python3 - "$ROOT" "$@" <<'PY'
import os, pathlib, sys
repo = sys.argv[1]
wanted = sys.argv[2:]
cands = [
    os.environ.get("VIBESYSTEMS_SECRETS_FILE", ""),
    os.path.expanduser("~/Documents/VibeSystems/secrets.env"),
    os.path.expanduser("~/.config/vibesystems/secrets.env"),
    os.path.expanduser("~/VibeSystems/secrets.env"),
    os.path.expanduser("~/Documents/secrets.env"),
    os.path.join(repo, "secrets.env"),
]
kv = {}
for c in cands:
    if c and os.path.isfile(c):
        for raw in pathlib.Path(c).read_text(encoding="utf-8", errors="ignore").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip()
            if k.startswith("export "):
                k = k[7:].strip()
            v = v.strip()
            if len(v) >= 2 and ((v[0] == '"' and v[-1] == '"') or (v[0] == "'" and v[-1] == "'")):
                v = v[1:-1]
            kv.setdefault(k, v)
        break
for k in wanted:
    if kv.get(k):
        sys.stdout.write(kv[k])
        break
PY
}

VERSION="$(grep -E '^VERSION=' scripts/package-app.sh | head -1 | cut -d= -f2 | tr -d '"')"
BUILD="$(grep -E '^BUILD=' scripts/package-app.sh | head -1 | cut -d= -f2 | tr -d '"')"
ARCH="$(uname -m)"
PRODUCT_NAME="Findaro"
LEGACY_NAME="Ordena"
DMG_NAME="${PRODUCT_NAME}-${VERSION}-${ARCH}.dmg"
LEGACY_DMG_NAME="${LEGACY_NAME}-${VERSION}-${ARCH}.dmg"
HOST="${FINDARO_SSH_HOST:-${ORDENA_SSH_HOST:-vps}}"
REMOTE_DIR="${FINDARO_REMOTE_DIR:-${ORDENA_REMOTE_DIR:-/var/www/ordena}}"
PUBLIC_BASE="${FINDARO_PUBLIC_BASE:-https://ordena.iareal.net}"
ENTITLEMENTS="$ROOT/Resources/Ordena.entitlements"

FINDARO_DMG="$ROOT/dist/${DMG_NAME}"
LEGACY_DMG="$ROOT/dist/${LEGACY_DMG_NAME}"

if [[ "${FINDARO_FORCE_REBUILD:-0}" != "1" && -f "$FINDARO_DMG" && -f "$LEGACY_DMG" ]] \
  && xcrun stapler validate "$FINDARO_DMG" >/dev/null 2>&1 \
  && xcrun stapler validate "$LEGACY_DMG" >/dev/null 2>&1; then
  echo "==> Reutilizando DMGs notarizados existentes (${VERSION}, build ${BUILD})…"
else
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
fi

SHA256="$(shasum -a 256 "$LEGACY_DMG" | awk '{print $1}')"
FINDARO_SHA="$(shasum -a 256 "$FINDARO_DMG" | awk '{print $1}')"

LOCAL_FEED="$ROOT/dist/latest.json"
LOCAL_SIG="$ROOT/dist/latest.json.sig"

cat > "$LOCAL_FEED" <<EOF
{
  "version": "${VERSION}",
  "build": ${BUILD},
  "tag": "v${VERSION}",
  "dmg_url": "${PUBLIC_BASE}/downloads/${LEGACY_DMG_NAME}",
  "notes_url": "${PUBLIC_BASE}/",
  "sha256": "${SHA256}",
  "findaro_dmg_url": "${PUBLIC_BASE}/downloads/${DMG_NAME}",
  "findaro_sha256": "${FINDARO_SHA}"
}
EOF

echo "==> Firmando latest.json con Ed25519…"
"$ROOT/scripts/sign-feed.swift" "$LOCAL_FEED" "$LOCAL_SIG"

echo "==> Publicando en ${HOST}:${REMOTE_DIR}…"
scp "$FINDARO_DMG" "${HOST}:${REMOTE_DIR}/downloads/${DMG_NAME}"
scp "$FINDARO_DMG" "${HOST}:${REMOTE_DIR}/downloads/${PRODUCT_NAME}-latest.dmg"
scp "$FINDARO_DMG" "${HOST}:${REMOTE_DIR}/downloads/${PRODUCT_NAME}-current.dmg"
scp "$LEGACY_DMG" "${HOST}:${REMOTE_DIR}/downloads/${LEGACY_DMG_NAME}"
scp "$LEGACY_DMG" "${HOST}:${REMOTE_DIR}/downloads/${LEGACY_NAME}-latest.dmg"
scp "$LEGACY_DMG" "${HOST}:${REMOTE_DIR}/downloads/${LEGACY_NAME}-current.dmg"
scp "$LOCAL_FEED" "${HOST}:${REMOTE_DIR}/downloads/latest.json"
scp "$LOCAL_SIG" "${HOST}:${REMOTE_DIR}/downloads/latest.json.sig"

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

echo "==> Purgando caché de Cloudflare…"
CF_TOKEN="${CLOUDFLARE_API_TOKEN:-${CF_API_TOKEN:-}}"
if [[ -z "$CF_TOKEN" ]]; then
  CF_TOKEN="$(get_secret_val CLOUDFLARE_API_TOKEN CF_API_TOKEN)"
fi
# Zona iareal.net (pública). Override con CLOUDFLARE_ZONE_ID si cambia.
CF_ZONE="${CLOUDFLARE_ZONE_ID:-${CF_ZONE_ID:-$(get_secret_val CLOUDFLARE_ZONE_ID CF_ZONE_ID)}}"
CF_ZONE="${CF_ZONE:-909879d629009acbb4377720753dadf7}"

PURGE_PAYLOAD="$(cat <<JSON
{
  "files": [
    "${PUBLIC_BASE}/downloads/latest.json",
    "${PUBLIC_BASE}/downloads/latest.json.sig",
    "${PUBLIC_BASE}/downloads/${DMG_NAME}",
    "${PUBLIC_BASE}/downloads/${PRODUCT_NAME}-latest.dmg",
    "${PUBLIC_BASE}/downloads/${PRODUCT_NAME}-current.dmg",
    "${PUBLIC_BASE}/downloads/${LEGACY_DMG_NAME}",
    "${PUBLIC_BASE}/downloads/${LEGACY_NAME}-latest.dmg",
    "${PUBLIC_BASE}/downloads/${LEGACY_NAME}-current.dmg"
  ]
}
JSON
)"

CF_PURGE_RESP=""
if [[ -n "$CF_TOKEN" ]]; then
  echo "Purgando caché en Cloudflare vía API (zone=${CF_ZONE})..."
  CF_PURGE_RESP="$(curl -4 -sS -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE}/purge_cache" \
    -H "Authorization: Bearer ${CF_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "${PURGE_PAYLOAD}" || true)"
fi

if ! printf '%s' "$CF_PURGE_RESP" | grep -q '"success":true'; then
  echo "Purga local sin éxito; intentando vía /root/.cloudflare.env en ${HOST}..."
  CF_PURGE_RESP="$(printf '%s' "${PURGE_PAYLOAD}" | ssh "$HOST" "CF_ZONE_DEFAULT='${CF_ZONE}' python3 -c '
import json, os, pathlib, sys, urllib.error, urllib.request
env_file = pathlib.Path(\"/root/.cloudflare.env\")
if not env_file.is_file():
    sys.stderr.write(\"ERROR: /root/.cloudflare.env no existe en el VPS.\\n\")
    sys.exit(2)
kv = {}
for raw in env_file.read_text(encoding=\"utf-8\", errors=\"ignore\").splitlines():
    line = raw.strip()
    if not line or line.startswith(\"#\") or \"=\" not in line:
        continue
    k, v = line.split(\"=\", 1)
    k = k.strip()
    if k.startswith(\"export \"):
        k = k[7:].strip()
    v = v.strip()
    if len(v) >= 2 and ((v[0] == \"\\\"\" and v[-1] == \"\\\"\") or (v[0] == \"\x27\" and v[-1] == \"\x27\")):
        v = v[1:-1]
    kv[k] = v
token = kv.get(\"CLOUDFLARE_API_TOKEN\") or kv.get(\"CF_API_TOKEN\") or \"\"
zone = kv.get(\"CLOUDFLARE_ZONE_ID\") or kv.get(\"CF_ZONE_ID\") or os.environ.get(\"CF_ZONE_DEFAULT\", \"\")
if not token or not zone:
    sys.stderr.write(\"ERROR: Faltan credenciales Cloudflare en /root/.cloudflare.env.\\n\")
    sys.exit(3)
payload = sys.stdin.read().encode(\"utf-8\")
req = urllib.request.Request(
    f\"https://api.cloudflare.com/client/v4/zones/{zone}/purge_cache\",
    data=payload,
    method=\"POST\",
    headers={\"Authorization\": f\"Bearer {token}\", \"Content-Type\": \"application/json\"},
)
try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        sys.stdout.write(resp.read().decode(\"utf-8\", errors=\"replace\"))
except urllib.error.HTTPError as err:
    sys.stdout.write(err.read().decode(\"utf-8\", errors=\"replace\"))
'" || true)"
fi

if ! printf '%s' "$CF_PURGE_RESP" | grep -q '"success":true'; then
  cat >&2 <<CF_ERR
ERROR: Falló la purga en Cloudflare (el release NO queda limpio en CDN).
Respuesta: ${CF_PURGE_RESP}

El token necesita permiso «Zone.Cache Purge» sobre iareal.net.
CF_ERR
  exit 1
fi
echo "Caché de Cloudflare purgada con éxito."

echo "Publicado v${VERSION}"
curl -sS "${PUBLIC_BASE}/downloads/latest.json"
echo
curl -sS "${PUBLIC_BASE}/downloads/latest.json.sig"
echo
