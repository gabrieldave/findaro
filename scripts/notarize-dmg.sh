#!/usr/bin/env bash
# Notariza un .dmg firmado con Developer ID.
# Requiere (en entorno, nunca en el repo):
#   APPLE_ID=...  APPLE_APP_SPECIFIC_PASSWORD=...  APPLE_TEAM_ID=YH6W55MP95
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${1:-}"
if [[ -z "$DMG" ]]; then
  DMG="$(ls -t "$ROOT"/dist/Ordena-*.dmg 2>/dev/null | head -1 || true)"
fi
[[ -n "$DMG" && -f "$DMG" ]] || { echo "Uso: $0 path/al/Ordena.dmg"; exit 1; }

: "${APPLE_ID:?Define APPLE_ID}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Define APPLE_APP_SPECIFIC_PASSWORD (appleid.apple.com → App-Specific Password)}"
TEAM_ID="${APPLE_TEAM_ID:-YH6W55MP95}"

echo "==> Enviando a notarytool: $DMG"
xcrun notarytool submit "$DMG" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

echo "==> Stapling…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "OK=$DMG"
