#!/bin/bash
# Ayudante de capturas y videos de FINDARO para marketing (macOS, bash 3.2 compatible).
# Estado: escrito por Claude sin acceso a un Mac -> NO PROBADO. Cursor debe validarlo con `prep` y `shot prueba`.
#
# Requisitos: permisos de Accesibilidad y Grabación de pantalla para la Terminal (o Cursor) que lo ejecute.
#
#   scripts/demo/capture.sh prep                 # comprueba entorno, versión y privacidad
#   scripts/demo/capture.sh window [W H]         # coloca la ventana de Findaro (por defecto 1280x800 pt)
#   scripts/demo/capture.sh shot P01-hero        # PNG de la ventana de Findaro
#   scripts/demo/capture.sh video V1-cortar 10   # video de la ventana, 10 s, con clics visibles
#   scripts/demo/capture.sh pack                 # comprime la carpeta de entrega en el Escritorio
set -euo pipefail

# Privacidad: oculta favoritos/ubicaciones personales en la UI durante capturas.
export FINDARO_DEMO_MODE=1
defaults write app.findaro.files findaro_demo_mode -bool true

APP_NAME="Findaro"
OUT="${FINDARO_CAPTURE_OUT:-$HOME/Desktop/FINDARO_CAPTURA_$(date +%Y%m%d)}"
MANIFEST="$OUT/manifest.tsv"
# Por defecto: casi fullscreen lógico (no 1280×800 fijo — en Retina las letras salían densas).
DEFAULT_W=0
DEFAULT_H=0

app_plist() {
  for p in "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"; do
    [ -f "$p/Contents/Info.plist" ] && { echo "$p/Contents/Info.plist"; return; }
  done
}

build_id() {
  local pl; pl="$(app_plist)"
  [ -n "$pl" ] || { echo "desconocida"; return; }
  echo "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$pl") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$pl"))"
}

# Devuelve "x,y,w,h" en puntos de la ventana frontal de Findaro
bounds() {
  osascript <<EOF
tell application "System Events" to tell process "$APP_NAME"
  set {x, y} to position of front window
  set {w, h} to size of front window
end tell
return (x as text) & "," & (y as text) & "," & (w as text) & "," & (h as text)
EOF
}

ensure_out() {
  mkdir -p "$OUT/png" "$OUT/video"
  [ -f "$MANIFEST" ] || printf 'utc\tid\ttipo\tarchivo\tancho\talto\tsha256\tbuild\tusuario_macos\trevision_privacidad\n' > "$MANIFEST"
}

ensure_privacy_sandbox() {
  local sandbox="${FINDARO_SANDBOX:-/tmp/FINDARO-QA-Sandbox}"
  if [ ! -d "$sandbox" ] && [ ! -d "$HOME/Documents/FINDARO-Demo" ]; then
    echo "Inicializando entorno ficticio aislado en $sandbox..."
    mkdir -p "$sandbox/ORIGEN/Documentos" "$sandbox/ORIGEN/Proyectos" "$sandbox/DESTINO"
    printf "Informe de ventas ficticio Q4 2026\n" > "$sandbox/ORIGEN/Documentos/informe-q4.txt"
    printf "Archivo de proyecto de demostracion\n" > "$sandbox/ORIGEN/Proyectos/proyecto-alfa.txt"
    printf "Datos sinteticos de prueba sin informacion personal\n" > "$sandbox/LEEME.txt"
  fi
}

record() { # id tipo archivo
  local f="$3" w="-" h="-"
  if [ "$2" = "png" ]; then
    w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tREVISADO_PRIVACIDAD_SANDBOX\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$1" "$2" "${f#$OUT/}" "$w" "$h" \
    "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$(build_id)" "$(whoami)" >> "$MANIFEST"
  echo "OK $f"
}

cmd="${1:-help}"
case "$cmd" in
  prep)
    ensure_privacy_sandbox
    echo "Findaro: $(build_id)"
    echo "Usuario macOS: $(whoami)"; [ "$(whoami)" = "demo" ] || echo "  AVISO: usa la cuenta 'demo' para que no salgan tu nombre ni tus rutas"
    echo "Apariencia: $(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)"
    echo "Pantallas:"; system_profiler SPDisplaysDataType | grep -E 'Resolution|Retina|Main Display' | sed 's/^ */  /'
    if [ -d "$HOME/Library/CloudStorage" ] && [ -n "$(ls -A "$HOME/Library/CloudStorage" 2>/dev/null)" ]; then
      echo "  AVISO: hay servicios en ~/Library/CloudStorage (Google Drive, Dropbox...). Desconéctalos antes de grabar:"; ls "$HOME/Library/CloudStorage" | sed 's/^/    /'
    fi
    ls /Volumes | grep -v '^Macintosh HD$' | sed 's/^/  Volumen montado: /' || true
    pgrep -x "$APP_NAME" >/dev/null && echo "Findaro abierto: sí" || echo "Findaro abierto: NO (ábrelo antes de capturar)"
    [ -d "$HOME/Documents/FINDARO-Demo" ] && echo "Set de prueba: sí" || echo "Set de prueba: NO -> python3 scripts/demo/make_demo_dataset.py"
    ;;
  window)
    # Boost tipográfico para capturas (letras legibles en web/redes).
    defaults write app.findaro.files findaro_ui_text_boost -float 0.12
    # Si no pasan W/H: 96% × 94% del escritorio visible (pt), centrado.
    if [ -z "${2:-}" ] || [ "${2:-0}" = "0" ]; then
      eval "$(osascript <<'OSA'
tell application "Finder"
  set {l, t, r, b} to bounds of window of desktop
end tell
set W to round ((r - l) * 0.96)
set H to round ((b - t) * 0.92)
if W < 1100 then set W to 1100
if H < 720 then set H to 720
return "W=" & W & "; H=" & H & "; L=" & l & "; T=" & t & "; R=" & r & "; B=" & b
OSA
)"
    else
      W="${2}"; H="${3:-800}"
      eval "$(osascript <<OSA
tell application "Finder"
  set {l, t, r, b} to bounds of window of desktop
end tell
return "L=" & l & "; T=" & t & "; R=" & r & "; B=" & b
OSA
)"
    fi
    osascript <<EOF
tell application "$APP_NAME" to activate
delay 0.4
tell application "System Events" to tell process "$APP_NAME"
  set size of front window to {$W, $H}
  set position of front window to {round (($L + $R - $W) / 2), round (($T + $B - $H) / 2)}
end tell
EOF
    echo "Ventana en $(bounds) (x,y,ancho,alto en puntos) text_boost=0.12"
    ;;
  shot)
    id="${2:?falta el id, p. ej. P01-hero}"; ensure_out
    osascript -e "tell application \"$APP_NAME\" to activate"; sleep 0.6
    f="$OUT/png/$id.png"
    screencapture -x -R"$(bounds)" "$f"
    record "$id" png "$f"
    ;;
  video)
    id="${2:?falta el id, p. ej. V1-cortar}"; secs="${3:-10}"; ensure_out
    osascript -e "tell application \"$APP_NAME\" to activate"; sleep 0.6
    f="$OUT/video/$id.mov"
    echo "Grabando $secs s en 3..."; sleep 1; echo "2..."; sleep 1; echo "1..."; sleep 1
    screencapture -v -k -V "$secs" -R"$(bounds)" "$f"
    record "$id" video "$f"
    ;;
  pack)
    [ -d "$OUT" ] || { echo "No hay $OUT"; exit 1; }
    z="$HOME/Desktop/$(basename "$OUT").zip"
    (cd "$(dirname "$OUT")" && ditto -c -k --keepParent "$(basename "$OUT")" "$z")
    echo "Listo: $z ($(du -h "$z" | cut -f1))"
    ;;
  *)
    sed -n '2,13p' "$0"
    ;;
esac
