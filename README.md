# Ordena — organiza tus carpetas mejor que el Finder

App nativa de macOS (SwiftUI) para ordenar Descargas y otras carpetas por tipo + fecha, con selección tipo Finder, bandeja y limpieza por peso.

## Instalar (recomendado)

```bash
./scripts/make-dmg.sh
```

Eso genera en el Escritorio:

`Ordena-0.1.0-arm64.dmg`

1. Doble clic al `.dmg` → monta el volumen **Ordena …** (aparece en Finder → Ubicaciones, como DICloak).
2. Arrastra **Ordena.app** a **Aplicaciones**.
3. Expulsa el disco e inicia Ordena desde Launchpad / Spotlight (`⌘Espacio`).

Solo empaquetar e instalar local:

```bash
./scripts/package-app.sh
open /Applications/Ordena.app
```

## Requisitos

- macOS 15+
- Apple Silicon (`arm64`)

## Desarrollo

```bash
swift test
./scripts/package-app.sh
```
