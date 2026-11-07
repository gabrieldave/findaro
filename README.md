# Findaro — el espacio de trabajo de archivos para Mac

**Findaro** es un explorador avanzado de archivos para macOS, diseñado para quienes necesitan más control y velocidad que un navegador de archivos convencional.

Doble panel, organización visual, bandeja de transferencias, Smart Merge con verificación SHA-256 y asistente local opcional con Ollama.

> Marca comercial provisional. El bundle identifier heredado se conserva durante esta fase para no romper la continuidad de instalación y actualización.

**Versión de código:** `0.1.74` · **Apple Silicon** · **Deployment target:** macOS 15+

## La idea de Findaro

Menos ventanas. Más contexto. Más control sobre tus archivos.

- **Dos paneles:** trabaja con origen y destino al mismo tiempo.
- **Organización inteligente:** orden por tipo, fecha, tamaño y reglas guardadas.
- **Smart Merge:** compara contenido mediante SHA-256 y permite revisar antes de completar una fusión.
- **Bandeja de archivos:** reúne elementos para moverlos o copiarlos en otro momento.
- **Asistente local:** integración opcional con Ollama; tus archivos permanecen en tu Mac.
- **Actualización automática:** los paneles observan cambios del sistema de archivos.

## Instalar y actualizar

Durante la transición de marca se conserva el canal de actualización existente:

- Sitio temporal: https://ordena.iareal.net/
- Feed: https://ordena.iareal.net/downloads/latest.json

Para generar el instalador local:

```bash
./scripts/make-dmg.sh
```

El DMG se genera en `dist/Findaro-0.1.74-arm64.dmg` y también se copia al Escritorio.

1. Abre el DMG.
2. Arrastra `Findaro.app` a Aplicaciones.
3. Abre Findaro desde Launchpad, Spotlight o el Dock.

## Requisitos

- macOS 15 o posterior.
- Apple Silicon (arm64).
- Para compilar y probar: Xcode completo y Swift 6.4 o compatible.
- Entorno CI previsto: runner `xcode-27`.

## Desarrollo

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift build --product Orden
./scripts/package-app.sh
```

El producto Swift Package y el ejecutable de compilación conservan internamente el nombre `Orden` durante la transición. La aplicación empaquetada y su nombre visible son `Findaro`.

## Funciones incluidas

- Exploración en lista e iconos.
- Doble panel Origen | Destino.
- Actualización automática mediante FSEvents.
- Omnibox de rutas (`⌘L`).
- Perfil de teclado Explorer (Enter abre / F2 renombra).
- Archivos ocultos (`⌘⇧.`) y vista plana.
- Smart Merge con SHA-256, rollback y aprobación.
- Bandeja de archivos y operaciones de transferencia.
- Atajo global configurable para abrir Descargas.
- Asistente local opcional con Ollama.

## Identidad visual

El sistema visual usa una base grafito/azul noche, superficies de profundidad sutil, acento azul eléctrico y violeta, y un símbolo geométrico propio. Se prioriza contraste, legibilidad y densidad de información sobre adornos.

## Estado del producto

Esta rama contiene el primer pase de identidad y experiencia visual Findaro. Antes de distribuir una versión comercial deben completarse pruebas funcionales en macOS, revisión de licencias y disponibilidad de marca, firma Developer ID y notarización.

## Contacto

VibeSystems / IAreal.
