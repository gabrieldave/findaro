# Ordena — organiza tus carpetas mejor que el Finder

App nativa de macOS (SwiftUI + AppKit) para Descargas y otras carpetas: orden por tipo/fecha, doble panel, bandeja tipo Dropover, Smart Merge y asistente local (Ollama opcional).

**Versión actual:** `0.1.73` · Bundle ID `app.ordena.files` · Apple Silicon

## Instalar (recomendado)

Descarga pública (actualizaciones automáticas):

- https://ordena.iareal.net/
- Feed: https://ordena.iareal.net/downloads/latest.json

O genera el DMG en local:

```bash
./scripts/make-dmg.sh
```

En el Escritorio queda `Ordena-0.1.73-arm64.dmg`:

1. Doble clic → monta el volumen **Ordena …**
2. Arrastra **Ordena.app** a **Aplicaciones**
3. Abre desde Launchpad / Spotlight (`⌘Espacio`)

Solo empaquetar e instalar:

```bash
./scripts/package-app.sh
open /Applications/Ordena.app
```

Publicar update al VPS:

```bash
./scripts/publish-update.sh
```

## Requisitos

- macOS 15+ (deployment target; no bajar sin acuerdo)
- Apple Silicon (`arm64`)
- Desarrollo validado: **macOS 27** + **Xcode 27.2** + **Swift 6.4**

## Desarrollo

Usa el Xcode.app completo (no solo Command Line Tools):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift build --product Orden
./scripts/package-app.sh
```

CI (GitHub Actions): runner `xcode-27` (macOS 27 + Xcode 27).

## Qué incluye (0.1.73)

- **Refresco automático** de paneles con FSEvents (descargas, renombres, borrados externos)
- **Doble panel** Origen | Destino; clic en vacío activa el panel
- **Omnibox** de ruta (`⌘L`)
- Perfil **Explorer**: Enter abre / F2 renombra (Ajustes)
- **Cut visual** (`⌘X` atenúa hasta pegar)
- **Ocultos** (`⌘⇧.`) y **vista plana**
- **Smart Merge** con SHA-256, rollback y aprobación
- **TransferQueue** con progreso y verify de tamaño (transfers entre paneles)
- Atajo global **⌃⌥O** · ✕ oculta la app (no cierra)

## Documentación

- `docs/PANEL-AUTO-REFRESH.md` — FSEvents y paneles
- `docs/PARA-CLAUDE.md` — briefing de producto

## Licencia / contacto

Producto VibeSystems / IAreal · WhatsApp: https://wa.me/525645674407
