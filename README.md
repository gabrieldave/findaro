# Ordena

Explorador y gestor inteligente de archivos para macOS, construido con SwiftUI y Swift Package Manager. Ayuda a explorar, buscar, comparar, organizar y transferir archivos; incluye un asistente opcional conectado a Ollama para trabajar con modelos de IA locales.

> El nombre comercial y la identidad visual están en evaluación. Los identificadores técnicos actuales se mantienen como Ordena hasta aprobar la marca definitiva.

## Funciones
- Exploración de archivos y carpetas con vistas adaptativas.
- Panel doble, favoritos, bandeja temporal y operaciones de archivo.
- Búsqueda recursiva y búsqueda de contenido.
- Análisis de tamaños y detección de posibles duplicados.
- Vista previa de fusión de carpetas.
- Asistente opcional con Ollama y aprobación de operaciones que modifican archivos.

## Requisitos
- macOS 15 o posterior.
- Apple Silicon (arm64) como plataforma objetivo actual.
- Xcode Command Line Tools y Swift 6.
- Ollama opcional para el asistente local.

## Desarrollo
    swift test
    swift build -c release

Para crear e instalar localmente:
    ./scripts/package-app.sh
    open /Applications/Ordena.app

Para generar un DMG:
    ./scripts/make-dmg.sh

Revisa los scripts antes de ejecutarlos: el empaquetado local puede instalar o reemplazar una copia de la aplicación en Aplicaciones.

## Firma y notarización
La compilación y la firma de desarrollo no equivalen a una distribución notarizada. Para distribuir fuera de la Mac App Store se necesita:
1. Certificado Developer ID Application válido en el llavero del Mac de compilación.
2. Hardened Runtime y entitlements mínimos compatibles con las funciones reales.
3. Firma de binarios y componentes anidados.
4. Envío mediante notarytool con credenciales configuradas localmente.
5. Resultado aceptado por Apple, stapling del ticket y validación con spctl y codesign.

No almacenes certificados, claves privadas, contraseñas ni perfiles de autenticación en este repositorio. La firma y notarización de lanzamiento se realizarán en un Mac autorizado. Este repositorio no afirma que el artefacto actual esté notarizado.

## Seguridad de operaciones
Las operaciones de escritura deben validar rutas, revisar conflictos y conservar la posibilidad de recuperación. La fusión de carpetas se bloquea cuando la vista previa está incompleta o hay conflictos de tipo archivo/carpeta. El origen solo se envía a la Papelera después de que la copia termine y se verifique.

## Estado
En desarrollo activo. Las versiones, el número de compilación y la identidad de marca se actualizarán al preparar un lanzamiento verificable.
