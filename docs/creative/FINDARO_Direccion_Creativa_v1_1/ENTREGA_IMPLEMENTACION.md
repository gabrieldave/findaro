# FINDARO — entrega implementación dirección creativa v1.1

**Rama:** `feature/findaro-brand-redesign`  
**Versión empaquetada:** `0.1.75` (build 81)  
**Bundle ID:** `app.findaro.files` (sin cambios)  
**App compilada:** `/Applications/Findaro.app` y `/Users/daveax/Projects/orden/dist/Findaro.app`

## Qué se implementó
- Tokens de marca (azul noche / eléctrico / violeta / cian) en claro y oscuro.
- Tipografía SF Pro nativa (sin diseño rounded en chrome).
- Sidebar premium con marca FINDARO (SF Symbol + wordmark; sin logo dibujado).
- Jerarquía de acciones: primaria azul, IA violeta, destructiva roja.
- Omnibox / breadcrumbs, bandeja, doble panel, selección y estados de transferencia.
- Icono AppIcon.icns **conservado** (no regenerado).

## Capturas reales
Ver carpeta `capturas/`:
1. `01_ventana_principal.png`
2. `02_doble_panel.png`
3. `03_seleccion_y_bandeja.png`
4. `04_modo_claro.png`

## QA
- `swift build -c release --product Orden` — OK
- `swift test` — 54 tests, 0 fallos
- Empaquetado `scripts/package-app.sh` — OK
- Sin merge a `main`, sin publicar / notarizar.
