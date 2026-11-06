#!/usr/bin/env bash
# Registra Ordena como app preferida para abrir carpetas (lo que macOS permita).
# No elimina Finder: el sistema y el stack del Dock siguen dependiendo de Finder.
set -euo pipefail

APP="/Applications/Ordena.app"
BUNDLE_ID="app.ordena.files"

if [[ ! -d "$APP" ]]; then
  echo "No está $APP — corre antes: ./scripts/package-app.sh"
  exit 1
fi

# Re-registrar en Launch Services
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

if command -v duti >/dev/null 2>&1; then
  duti -s "$BUNDLE_ID" public.folder all
  duti -s "$BUNDLE_ID" public.directory all
  echo "OK via duti: carpetas → Ordena"
else
  echo "Tip: brew install duti   (opcional, más fiable)"
  echo "También: abre Ordena → Archivo+ → «Usar Ordena para abrir carpetas…»"
fi

echo
echo "Prueba:"
echo "  open -a Ordena ~/Downloads"
echo "  # o clic derecho en carpeta → Abrir con → Ordena → Siempre"
echo
echo "Límite macOS: el triángulo ▼ del Dock (stacks) sigue abriendo Finder."
echo "Arrastra una carpeta al icono de Ordena en el Dock para abrirla ahí."
