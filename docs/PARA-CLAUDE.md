# Ordena — briefing para análisis (Claude)

**Repo:** https://github.com/gabrieldave/orden  
**Commit actual:** ver `git log -1`  
**Producto:** app nativa macOS (SwiftUI + AppKit) alternativa al Finder para organizar Descargas/carpetas.  
**Bundle ID:** `app.ordena.files` · **Versión:** 0.1.0 · **Arch:** arm64 · **mín. OS:** macOS 15

---

## Qué es / qué no es

- **Sí:** explorador de carpetas con sidebar fijo, filtros, bandeja tipo Dropover, drag multi-archivo, drop en carpetas, undo, atajo global ⌃⌥O, handler parcial de carpetas.
- **No:** no puede reemplazar Finder del sistema (Dock stacks ▼, algunos diálogos del SO). Límite de Apple.

---

## Arquitectura

| Capa | Path | Rol |
|------|------|-----|
| App UI | `Sources/OrdenApp/` | SwiftUI ventana, toolbar, gestos, menús |
| Core | `Sources/OrdenCore/` | FS puro: listar, categorías, sort, copy/move, prefs |
| Tests | `Tests/OrdenTests/` | FileOps, categorías, sort, descargas del día |
| Empaque | `scripts/package-app.sh` + `make-dmg.sh` | `.app` adhoc + `.dmg` |

### Piezas críticas (App)

- `BrowserModel.swift` — estado: ruta, selección, multi-select, bandeja, undo, dropPaths, Descargados hoy.
- `ContentView.swift` — layout HStack sidebar fijo (~212) + detalle; toolbar; Settings.
- `FileDragArmMonitor` + `FileDragArmChrome` — hold ~1s arma drag; clic corto = select.
- `FolderDragBridge` — drag multi con badge N.
- `FolderDropTarget` — hover verde + onDrop mueve/copia (⌥) dentro de carpeta.
- `DropShelfView` — bandeja ⌘C/⌘X/⌘V.
- `OpenFolderBridge` — LSSetDefaultRoleHandlerForContentType + open URLs.
- `GlobalHotKey` — Carbon ⌃⌥O → frente + Descargas.
- `SelectionCancelMonitor` — Esc cancela multi + arm.
- `AppDelegate` — activation policy, open files, hotkey, auto-register folder handler.

### Core

- `DirectoryLoader`, `FileEntry`, `FileCategory`, `SortEngine`/`SortRule`
- `FileOps` — move/copy + `TransferPair` para undo
- `DownloadDayFilter` — metadatos “descargado hoy”
- `PreferencesStore` — favoritos / scope

### Regla de UI (repo)

Sidebar **nunca** colapsa: `HStack` + ancho fijo, no `NavigationSplitView`. Ver `.cursor/rules/sidebar-fijo.mdc`.

---

## Flujo de usuario clave

1. Abrir Descargas (⌘⇧L o ⌃⌥O).
2. Filtrar / modo **Descargados** (solo hoy).
3. Selección: clic, marquee, ⌘/modo varios; Esc limpia.
4. Hold 1s → arrastrar; soltar en carpeta (verde) = mover; ⌥ = copiar.
5. Bandeja: ⌘C/⌘X acumulan; ⌘V suelta en carpeta actual.
6. ⌘Z deshace último move/copy de la app.

---

## Distribución actual

- Firma: **adhoc** (`codesign -s -`), sin Apple Developer ID → Gatekeeper en otra Mac pide clic derecho → Abrir.
- Artefacto: `Ordena-0.1.0-arm64.dmg` (app + enlace a Aplicaciones).
- Instalación otra Mac: montar DMG → arrastrar a Aplicaciones → clic derecho Abrir la 1ª vez.
- Para App Store / notarización: hace falta certificado Developer ID + `notarytool`.

---

## Cómo build

```bash
swift test
./scripts/package-app.sh          # → dist/Ordena.app + /Applications
./scripts/make-dmg.sh             # → Escritorio Ordena-0.1.0-arm64.dmg
```

---

## Pedidos típicos al analizar

1. Seguridad FS (sandbox? permisos Full Disk Access?).
2. Robustez drag/drop vs Finder.
3. Roadmap: notarización, iCloud/network volumes, pestañas, búsqueda Spotlight.
4. Deuda: warnings Sendable en pasteboard closures; SPM sin Xcode project.
5. UX: onboarding del atajo ⌃⌥O y límites vs Finder.

---

## Archivos a leer primero

1. `Package.swift`
2. `Sources/OrdenApp/BrowserModel.swift`
3. `Sources/OrdenApp/ContentView.swift` (toolbar + grid)
4. `Sources/OrdenCore/FileOps.swift`
5. `scripts/package-app.sh`
