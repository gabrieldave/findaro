#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'ERROR: Las fixtures están previstas para demostración de FINDARO en macOS.' >&2
  exit 2
fi

TEMP_BASE="${TMPDIR:-/tmp}"
DEMO="$(mktemp -d "${TEMP_BASE%/}/findaro-web-demo.XXXXXX")"
ORIGEN="$DEMO/ORIGEN"
DESTINO="$DEMO/DESTINO"
mkdir -p "$ORIGEN/Documentos" "$ORIGEN/Imagenes" "$ORIGEN/Proyectos" "$ORIGEN/Recursos" \
         "$DESTINO/Documentos" "$DESTINO/Imagenes" "$DESTINO/Proyectos"

printf 'Documento de ejemplo para FINDARO.\n' > "$ORIGEN/Documentos/resumen-proyecto.txt"
printf '1,Investigacion\n2,Diseno\n3,Revision\n' > "$ORIGEN/Proyectos/plan-de-trabajo.csv"
printf 'Notas del conjunto de demostracion.\n' > "$ORIGEN/Documentos/notas-del-equipo.txt"
printf 'Recurso de demostracion sin datos reales.\n' > "$ORIGEN/Recursos/instrucciones.txt"
printf 'Archivo de prueba con contenido igual.\n' > "$ORIGEN/Documentos/coincidencia.txt"
printf 'Archivo de prueba con contenido igual.\n' > "$DESTINO/Documentos/coincidencia.txt"
printf 'VERSION ORIGEN: ejemplo de conflicto.\n' > "$ORIGEN/Documentos/conflicto.txt"
printf 'VERSION DESTINO: ejemplo de conflicto distinto.\n' > "$DESTINO/Documentos/conflicto.txt"
printf 'Archivo previo en el destino.\n' > "$DESTINO/Proyectos/archivo-existente.txt"
printf 'Demo FINDARO sin datos privados.\n' > "$DEMO/LEEME.txt"

printf '\nCAPTURA SEGURA — CARPETAS CREADAS:\n'
printf 'ORIGEN:  %s\n' "$ORIGEN"
printf 'DESTINO: %s\n' "$DESTINO"
printf '\nAbre estas rutas EN FINDARO. No se modificaron carpetas personales.\n'
printf 'Guarda estas rutas en el handoff para entender el escenario capturado.\n'
printf 'La carpeta de prueba NO se elimina automaticamente.\n'
