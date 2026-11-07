#!/usr/bin/env bash
# Crea un .dmg comercial (como DICloak): montas el disco → arrastras a Aplicaciones.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRODUCT_NAME="Ordena"
VERSION="0.1.52"
ARCH="$(uname -m)"
# Nombre del volumen al montar (aparece en Finder → Ubicaciones)
VOL_NAME="${PRODUCT_NAME} ${VERSION}-${ARCH}"
DMG_NAME="${PRODUCT_NAME}-${VERSION}-${ARCH}.dmg"

echo "==> Empaquetando ${PRODUCT_NAME}.app…"
"$ROOT/scripts/package-app.sh"

APP_SRC="$ROOT/dist/${PRODUCT_NAME}.app"
[[ -d "$APP_SRC" ]] || { echo "No está $APP_SRC"; exit 1; }

STAGE="$ROOT/dist/dmg-stage"
RW_DMG="$ROOT/dist/${PRODUCT_NAME}-rw.dmg"
OUT_DMG="$ROOT/dist/${DMG_NAME}"

rm -rf "$STAGE" "$RW_DMG" "$OUT_DMG"
mkdir -p "$STAGE"

cp -R "$APP_SRC" "$STAGE/${PRODUCT_NAME}.app"
# Atajo estándar: arrastrar la app a Aplicaciones
ln -s /Applications "$STAGE/Applications"

# README breve dentro del DMG
cat > "$STAGE/Léeme.txt" <<EOF
${PRODUCT_NAME} — organiza tus carpetas mejor que el Finder.

Instalación:
1. Arrastra ${PRODUCT_NAME}.app a la carpeta Aplicaciones.
2. Abre ${PRODUCT_NAME} desde Launchpad o Spotlight (⌘Espacio).
3. Puedes expulsar este disco (eject) cuando termines.

Requisitos: macOS 15+, Apple Silicon (arm64).
EOF

echo "==> Creando imagen ${VOL_NAME}…"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDRW \
  "$RW_DMG" >/dev/null

echo "==> Comprimiendo…"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" >/dev/null
rm -f "$RW_DMG"
rm -rf "$STAGE"

# Copia fácil para compartir
cp -f "$OUT_DMG" "$HOME/Desktop/${DMG_NAME}"

SIZE=$(du -h "$OUT_DMG" | awk '{print $1}')
echo "DMG=$OUT_DMG ($SIZE)"
echo "DESKTOP=$HOME/Desktop/${DMG_NAME}"
echo "TIP=Doble clic al .dmg → monta el volumen «${VOL_NAME}» en Ubicaciones → arrastra a Aplicaciones"
