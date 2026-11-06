# Orden — un Finder mejor

App de macOS **aparte** del Finder de Apple. No parchea preferencias del sistema: es tu gestor de archivos con orden que sí se entiende.

## Abrir (esto es lo que importa)

Doble clic en:

- **Escritorio → `Orden.app`**
- o **`~/Applications/Orden.app`**

Debe aparecer en el Dock como **Orden**.

Para reconstruir:

```bash
cd ~/Projects/orden
./scripts/package-app.sh
open ~/Desktop/Orden.app
```

## Qué hace distinto al Finder

1. **Un solo modelo de orden** — sin pelear Arrange / Group / Sort.
2. **Frase visible** arriba con la regla actual.
3. **Descargas smart** — carpetas `01_…` por nombre; archivos por fecha.
4. **Preferencias propias** (no `.DS_Store`).
5. **Atajos** — Return/⌘↓ abrir · Space vista rápida · ⌘⌫ Papelera · ⌘↑ arriba.

## Tests

```bash
swift test
```
