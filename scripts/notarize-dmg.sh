#!/usr/bin/env bash
# Notariza un .dmg firmado con Developer ID.
# Requiere (en entorno, nunca en el repo):
#   APPLE_ID=...  APPLE_APP_SPECIFIC_PASSWORD=...  APPLE_TEAM_ID=YH6W55MP95
# NO ejecutar sin autorización explícita del director.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${1:-}"
if [[ -z "$DMG" ]]; then
  DMG="$(ls -t "$ROOT"/dist/Findaro-*.dmg 2>/dev/null | head -1 || true)"
fi
[[ -n "$DMG" && -f "$DMG" ]] || { echo "Uso: $0 path/al/Findaro.dmg"; exit 1; }

TEAM_ID="${APPLE_TEAM_ID:-YH6W55MP95}"
PROFILE="${NOTARY_KEYCHAIN_PROFILE:-ordena-notary}"

echo "==> Enviando a notarytool: $DMG"
if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait
elif xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$PROFILE" \
    --wait
else
  echo "Define APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD, o un perfil notarytool ($PROFILE)." >&2
  exit 1
fi

echo "==> Stapling…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "OK=$DMG"
