#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${FINDARO_CAPTURES_DIR:-$HOME/Downloads/FINDARO_CAPTURE_REVIEW}"

usage() {
  printf 'FINDARO Capturas\n'
  printf '  %s list\n' "$0"
  printf '  %s shoot <escena> <id_ventana>\n' "$0"
  printf '  Ejemplo: %s shoot doble-panel 473\n' "$0"
  printf '  Salida: %s\n' "$OUTPUT"
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'ERROR: Requiere un Mac real con FINDARO abierto.' >&2
  exit 2
fi

MODE="${1:-}"
case "$MODE" in
  list)
    echo $'ID\tAPLICACIÓN\tTAMAÑO\tTÍTULO'
    /usr/bin/swift "$DIR/list-windows.swift"
    ;;
  shoot)
    SCENE="${2:-}"
    ID="${3:-}"
    if [[ ! "$SCENE" =~ ^[a-z0-9][a-z0-9-]{1,55}$ ]]; then
      echo 'ERROR: Escena inválida. Utiliza minúsculas, números y guiones.' >&2; exit 3
    fi
    if [[ ! "$ID" =~ ^[0-9]{1,12}$ ]]; then
      echo 'ERROR: ID de ventana inválido. Ejecuta list antes.' >&2; exit 3
    fi
    WINDOW_MATCH="$(/usr/bin/swift "$DIR/list-windows.swift" | /usr/bin/awk -F '\t' -v id="$ID" '$1 == id { print $0 }')"
    if [[ -z "$WINDOW_MATCH" ]]; then
      echo 'ERROR: El ID elegido no es una ventana visible de FINDARO.' >&2; exit 4
    fi
    mkdir -p "$OUTPUT"
    STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
    FILE="$OUTPUT/${SCENE}-${STAMP}.png"
    # Screenshot nativo de macOS sobre la ventana REAL, sin sombra de ventana.
    /usr/sbin/screencapture -x -o -l "$ID" "$FILE"
    if [[ ! -s "$FILE" ]]; then echo 'ERROR: No se guardó la imagen.' >&2; exit 5; fi
    FILETYPE="$(/usr/bin/file -b "$FILE")"
    case "$FILETYPE" in
      PNG*) ;;
      *) echo 'ERROR: El formato no es PNG.' >&2; exit 6;;
    esac
    WIDTH="$(/usr/bin/sips -g pixelWidth "$FILE" | /usr/bin/awk '/pixelWidth:/ {print $2}')"
    HEIGHT="$(/usr/bin/sips -g pixelHeight "$FILE" | /usr/bin/awk '/pixelHeight:/ {print $2}')"
    HASH="$(/usr/bin/shasum -a 256 "$FILE" | /usr/bin/awk '{print $1}')"
    MANIFEST="$OUTPUT/manifest.tsv"
    if [[ ! -e "$MANIFEST" ]]; then
      printf 'utc\tscene\tfile\twidth\theight\tsha256\tprivacy_status\n' > "$MANIFEST"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\tPENDING_REVIEW\n' "$STAMP" "$SCENE" "$(basename "$FILE")" "$WIDTH" "$HEIGHT" "$HASH" >> "$MANIFEST"
    echo "CAPTURADA: $FILE (${WIDTH} x ${HEIGHT})"
    echo "SHA-256: $HASH"
    echo 'PRIVACIDAD: PENDING_REVIEW. Inspecciona la imagen antes de compartirla.'
    echo 'No se publicó ni se copió a web/public.'
    ;;
  *) usage; exit 2;;
esac
