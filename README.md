# Orden

Gestor de archivos para macOS que **sí recuerda** cómo quieres ordenar.

## El problema del Finder

Finder mezcla tres conceptos (`Arrange` / `Group` / `Sort`), olvida preferencias por carpeta y el orden natural falla. En macOS 27.0.1 seguía igual.

## Qué hace Orden distinto

1. **Un solo modelo de orden** — claves claras + «Carpetas arriba» siempre.
2. **Frase visible** en la barra: `Carpetas arriba · Nombre A→Z · números naturales`.
3. **Preferencias propias** (JSON en Application Support), no `.DS_Store`.
4. **Multi-criterio** — p. ej. Clase + Nombre.
5. **Orden natural** — `file2` antes que `file10`.

## Requisitos

- macOS 15+
- Xcode 27 / Swift 6

## Probar

```bash
cd ~/Projects/orden
swift test
swift run Orden
```

O:

```bash
./scripts/run.sh
```

## Estado

MVP local: lista + favoritos + motor de orden con tests. Aún no sustituye diálogos Abrir/Guardar del sistema.
