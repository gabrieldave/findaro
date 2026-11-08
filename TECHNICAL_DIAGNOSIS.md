# TECHNICAL_DIAGNOSIS — FINDARO (BLACK EYE)

**Fecha:** 8 de noviembre de 2026  
**Sistema anfitrión:** macOS 27.2 (Build 26B123), Apple Silicon (arm64)  
**Versión de Xcode:** Xcode 27.2 (Build 27B52), Swift 6.4.2  
**Repositorio de código:** `https://github.com/gabrieldave/orden`  
**Rama de trabajo:** `fix/findaro-functional-audit-2026-11-08`  
**Commit base auditado:** `57a0263` (origin/main)  
**Versión de Findaro en el sistema:** `0.1.103` (Build `109`), Bundle ID: `app.findaro.files`  
**Gobierno corporativo:** BLACK EYE AI Operating System v1.3.1 (`AI_START_HERE.md`, `manual/BLACK_EYE_MANUAL.md`, `protocols/APPROVALS.md`)  
**Rol operativo:** Modo de lectura, diagnóstico y propuesta (Antigravity). Sin autorización de publicación ni cambios de código previos a la aprobación del Director General.

---

## 1. Confirmaciones Previas (Requisitos de Inicio)

1. **Acceso al repositorio FINDARO:** Confirmado en `/Users/davidai/.cursor/ordena`.
2. **Lectura de instrucciones BLACK EYE y versión vigente:** Confirmada lectura de `AI_START_HERE.md` v1.3.1, `VERSION` (1.3.1), `CHANGELOG.md`, `protocols/APPROVALS.md`, `software/IMPLEMENTATION.md` y `protocols/HANDOFF.md`.
3. **Estado de Git y commit actual:** Rama sincronizada con `origin/main` en el commit auditado `57a0263`. Se creó la rama de aislamiento `fix/findaro-functional-audit-2026-11-08` conforme a la política de Git (Sección 8). Árbol limpio (`working tree clean`).
4. **Herramientas disponibles en Mac:**
   - Swift 6.4.2 (`swiftlang-6.4.2.1.9 clang-2100.4.1.1`).
   - Xcode 27.2 (`27B52`).
   - Git 2.54.0.
   - Ollama instalado en `/usr/local/bin/ollama`, proceso activo (`ollama serve`), modelo verificado `qwen3.5:9b` con runner `mlx`.
   - Soporte de automatización: `osascript`, `screencapture`, `ffmpeg`. Acceso a `System Events` operativo.
5. **Capacidad de compilar y ejecutar FINDARO:**
   - `swift test` ejecutado satisfactoriamente: 84 pruebas unitarias pasadas en 2.45s sin errores.
   - `swift build --product Orden` completado satisfactoriamente (0.28s).
   - Paquete instalado en `/Applications/Findaro.app` correspondiente a la versión 0.1.103 (109).
6. **Capacidad real de automatizar su interfaz:**
   - Scripting de interfaz disponible mediante AppleScript/System Events y `screencapture`.
   - Limitación técnica registrada: Interacciones complejas de arrastre multitáctil de ratón requieren emulación mediante eventos nativos o atajos accesibles del producto. Si una interacción no es verificable al 100% de forma sintética, se clasificará estrictamente como **NO VERIFICADA**.

---

## 2. Diagnóstico Técnico Detallado: Errores Funcionales (Auditoría 2026-11-08)

### ENV-04. Pestañas (Reordenamiento y Transferencia)
- **Archivos:** `Sources/OrdenApp/BrowserWindowSession.swift`, `Sources/OrdenApp/BrowserTabBar` (en el mismo archivo).
- **Causa raíz confirmada:**
  - `BrowserWindowSession` expone `@Published private(set) var tabs: [TabItem]`. No existen métodos para mover o reordenar pestañas (`moveTab(fromOffsets:toOffset:)` o reubicación por identificador).
  - En la vista `BrowserTabBar`, los chips de pestaña (`tabChip`) son botones simples dentro de un `HStack` horizontal. Carecen de modificadores de arrastre (`.onDrag`) y receptores de suelta (`.onDrop`) para permitir el reordenamiento visual o la transferencia de posición.
- **Impacto:** Las pestañas solo se pueden abrir (`⌘T`), alternar o cerrar (`⌘W`), pero el usuario no puede reorganizarlas arrastrándolas.

---

### ENV-06. Atajos de Teclado (Conflictos y Asignaciones Duplicadas)
- **Archivos:** `Sources/OrdenApp/HotkeyRecorderSheet.swift`, `Sources/OrdenCore/AppHotkey.swift`, `Sources/OrdenApp/BrowserModel.swift`.
- **Causa raíz confirmada:**
  - En `HotkeyRecorderSheet.swift`, el botón `Guardar` ejecuta directamente `browser.setKeyboardHotkey(definition.id, chord: draft)` sin verificar si `draft` ya está asignado a otra acción en `AppHotkeyCatalog.resolved(overrides: ...)`.
  - En `AppHotkey.swift`, el catálogo original contiene una colisión de fábrica en los valores por defecto:
    - `dual.moveToDest`: `defaultChord: .init(keyCode: 46, character: "m", command: true, shift: true)` (⌘⇧M).
    - `view.multi`: `defaultChord: .init(keyCode: 46, character: "m", command: true, shift: true)` (⌘⇧M).
  - La interfaz no muestra alertas de colisión ni lista qué acción resultaría desplazada o duplicada.

---

### ENV-09. Acerca de y Ayuda (Menú Help del Sistema)
- **Archivos:** `Sources/OrdenApp/OrdenApp.swift`.
- **Causa raíz confirmada:**
  - En `OrdenApp.swift` (`FindaroCommands`), se sustituye `.appInfo` y `.newItem`, pero **no se implementa** `CommandGroup(replacing: .help)`.
  - En macOS, el sistema genera automáticamente un menú "Ayuda" que busca un Help Book registrado en el `Info.plist`. Al no existir un Apple Help Book integrado, macOS despliega el diálogo estándar: *"La Ayuda de Findaro no está disponible"*.
- **Solución técnica:** Añadir `CommandGroup(replacing: .help)` con enlace/ventana modal de guía rápida de Findaro, atajos y referencia de uso, sin inventar documentación ajena a las funciones implementadas.

---

### SEL-02. Selección Avanzada (⌘+clic, ⇧+clic, Flechas y Rangos)
- **Archivos:** `Sources/OrdenApp/FileDragArmMonitor.swift`, `Sources/OrdenApp/BrowserModel.swift` (`clickSelect`, `commandRangeSelectForMove`, `selectRange`), `Sources/OrdenApp/SelectionCancelMonitor.swift`.
- **Causa raíz confirmada:**
  - **Fallo crítico de concepto:** En `BrowserModel.swift` (líneas 452–454):
    ```swift
    /// ⌘+clic = idéntico a ⇧+clic (`selectRange` desde el ancla), y deja el grupo en naranja.
    /// Clic a clic con ⌘ sostenido: 1, luego 2, luego 3 → va creciendo el bloque, igual que ⇧.
    func commandRangeSelectForMove(to id: String, pane: PaneFocus? = nil)
    ```
    El código anterior forzó que **⌘+clic se comportara como selección de rango (`selectRange`)** para un modo especial de arrastre denominado "modo naranja".
  - En macOS estándar, **⌘+clic es selección disyuntiva/alternada** (toggle individual: añade o quita un elemento específico sin tocar los intermedios).
  - Además, `FileDragArmMonitor.swift` intercepta a bajo nivel `leftMouseDown` cuando `cmd` está activo y consume el evento (`return nil`), impidiendo que SwiftUI procese clics aditivos estándar.
  - Al coexistir este secuestro de eventos con `selectRange` (que depende de `selectionAnchorID`), la selección por `⇧+flecha abajo` y rangos con scroll quedaba inconsistente o desincronizada.

---

### BUS-03. Búsqueda Global y Botón «En todas partes»
- **Archivos:** `Sources/OrdenApp/ContentView.swift` (líneas 507–516), `Sources/OrdenApp/BrowserModel.swift` (`useDownloadsStyleEverywhere`).
- **Causa raíz confirmada:**
  - En la barra superior, junto a "Subcarpetas" (búsqueda recursiva), se colocó el botón:
    ```swift
    Button {
        browser.useDownloadsStyleEverywhere()
    } label: {
        Label("En todas partes", systemImage: "globe")
    }
    ```
  - La función `useDownloadsStyleEverywhere()` no busca archivos en todo el sistema: aplica la regla de orden `.downloads` a nivel global en las preferencias (`applyRule(.downloads, scope: .everywhere)`).
  - La etiqueta «En todas partes» junto a un icono de globo terráqueo en la barra de búsqueda generó la expectativa de búsqueda global Spotlight en todo el disco.
- **Dictamen:** No es un fallo del motor de búsqueda sino una ambigüedad severa de UX/UI. Se debe clarificar la etiqueta a nivel de ordenación ("Aplicar orden global") o ubicarla en los controles de orden, manteniendo la búsqueda global real como una propuesta de ampliación sujeta a aprobación (G1/G2).

---

### TR-04. Arrastre entre Paneles (Doble Panel)
- **Archivos:** `Sources/OrdenApp/BrowserLayoutViews.swift` (líneas 233–265, 520–558), `Sources/OrdenApp/FolderDragBridge.swift`.
- **Causa raíz confirmada:**
  - En `BrowserLayoutViews.swift`, el gesto de arrastre sobre las filas/iconos comprueba:
    ```swift
    if browser.hasArmedFileDrag { ... }
    ```
    Si el archivo no fue previamente "armado" (mediante una pulsación prolongada de 1s o un ⌘+clic específico que lo tornara naranja), el gesto de arrastre **no inicia un arrastre de archivos nativo**, sino que activa la selección por marquesina/rectángulo (`DragGesture` de SwiftUI).
  - Por ello, tanto los usuarios habituados al comportamiento estándar de macOS como los scripts de automatización no conseguían arrastrar archivos entre paneles con un simple clic-y-arrastre sobre un elemento seleccionado.
  - El receptor `DualPaneDrop.swift` (`.onDrop(of: [UTType.fileURL])`) funciona correctamente cuando recibe URLs válidas; el defecto radicaba en el **desencadenamiento del arrastre emisor**.

---

### IA-02. Planificación y Renombrado (Pérdida de Extensión .txt)
- **Archivos:** `Sources/OrdenCore/AgentTools.swift` (líneas 430–440).
- **Causa raíz confirmada:**
  - En la función `AgentTools.extractAfter(text, keys:)`:
    ```swift
    let rest = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    let cut = rest.split(whereSeparator: { $0 == "." || $0 == "," || $0 == ";" }).first.map(String.init) ?? rest
    let cleaned = cut.trimmingCharacters(in: .whitespaces)
    ```
  - Al procesar la instrucción *"renombrar a QA-renombrado.txt"*, `cut` se divide por el carácter punto (`.`) y toma el primer elemento (`.first`), descartando inmediatamente la extensión `txt`.
  - El plan resultante propuso renombrar a `QA-renombrado` en lugar de `QA-renombrado.txt`.

---

### IA-04. Ollama (Discrepancia de Modelos y Respuestas HTTP 501)
- **Archivos:** `Sources/OrdenApp/OllamaClient.swift`, `Sources/OrdenCore/PreferencesStore.swift`, `Sources/OrdenApp/BrowserModel.swift`.
- **Causa raíz confirmada:**
  - **Discrepancia de modelos:**
    - `PreferencesStore` codifica como default de fábrica `ollamaModel = "qwen2.5:3b"`.
    - En el Mac actual, Ollama tiene instalado y activo únicamente `qwen3.5:9b` (runner `mlx`).
    - Cuando `OllamaClient.probe()` detecta los modelos locales y ejecuta `markAvailable(models:)`, selecciona el primer modelo disponible si el actual no existe, pero **no persiste esta corrección** en `PreferencesStore`.
    - Al abrir una nueva sesión o invocar `applyPreferences()`, se vuelve a cargar el valor almacenado en preferencias (`qwen2.5:3b`), provocando errores de modelo no encontrado (`HTTP 404`) o desincronización visual.
  - **Origen del HTTP 501:**
    - Ollama devuelve `HTTP 501 Not Implemented` cuando se invocan endpoints o parámetros que el runner subyacente (especialmente runners MLX o backends experimentales en Apple Silicon) no implementa, o cuando se transmiten estructuras no soportadas.
    - Se comprobó mediante prueba directa que `/api/generate` y `/api/chat` con `qwen3.5:9b` responden correctamente `200 OK` si el payload es estándar.
    - El cliente debe capturar y mapear adecuadamente cada código de estado HTTP (`404` modelo ausente, `501` función no implementada por el runner local, timeout) sin bloquear la interfaz y con un fallback transparente a reglas locales.

---

### IA-06 & BUS-08. Persistencia y Sincronización de Filtros y Ajustes
- **Archivos:** `Sources/OrdenCore/PreferencesStore.swift`, `Sources/OrdenApp/BrowserModel.swift`, `Sources/OrdenApp/ContentView.swift` (`SettingsView`), `Sources/OrdenApp/OrdenApp.swift`.
- **Causa raíz centralizada confirmada:**
  - En `OrdenApp.swift`, `SettingsView` utiliza una instancia aislada:
    ```swift
    @StateObject private var settingsBrowser = BrowserModel()
    ```
    Mientras que cada ventana y pestaña de navegación crea su propio `BrowserModel` con su propio `PreferencesStore`.
  - Cuando el usuario edita o crea un filtro o ajuste en `SettingsView`, se actualiza el `settingsBrowser` y se escribe el archivo `preferences.json` en disco.
  - **Sin embargo**, `PreferencesStore` no emite notificaciones (`NotificationCenter` o Combine subject) hacia el resto de las instancias en ejecución.
  - Las ventanas activas retienen en memoria RAM su copia antigua de `assistantShortcuts` y preferencias. Cuando esa ventana realiza cualquier operación posterior (guardar historial, cambiar vista, alternar ocultos), escribe sus preferencias en memoria sobre el archivo en disco, **sobrescribiendo y perdiendo las modificaciones hechas en Ajustes**.
  - Este defecto explica de forma unificada tanto **IA-06** (filtros que desaparecen) como **BUS-08** (ajustes editados que no se reflejan tras navegar).

---

### TR-13. Privacidad en Procedimiento de Grabación y Capturas
- **Archivos:** `FINDARO_paquete_grabacion_Cursor/scripts/demo/capture.sh`.
- **Causa raíz confirmada:**
  - El script `capture.sh` capturaba directamente las coordenadas de la ventana frontal de Findaro sin exigir ni validar que la aplicación estuviera navegando dentro de un directorio de pruebas aislado (`FINDARO-Demo` o `/tmp/FINDARO-QA-Sandbox`).
  - Al abrirse en la carpeta `Descargas` o `Documentos` real del usuario anfitrión, se expusieron nombres reales de archivos y volúmenes montados.
  - El defecto corresponde al arnés de pruebas y captura de QA, no al explorador de archivos.

---

## 3. Diagnóstico de Pruebas Bloqueadas

| Prueba | Componente | Causa del Bloqueo Original | Estrategia de Desbloqueo Seguro |
|---|---|---|---|
| **ENV-07. Atajo global** | `GlobalHotKey.swift` | Atajo Carbon `⌃⌥O` requiere evento global del sistema y ventana no modal. | Probar en sesión con ventana Findaro en segundo plano sin alterar atajos del sistema. |
| **ENV-08. Apariencia clara/oscura** | `Theme.swift`, `ContentView.swift` | Requiere alternar modo de apariencia del sistema o del entorno SwiftUI. | Probar mediante override en la vista (`.preferredColorScheme(.dark / .light)`) sin alterar la configuración del OS del usuario. |
| **NAV-07. Reordenar favoritos** | `ContentView.swift` (`favoritesDropZone`) | La lista de favoritos es un `ForEach` estático dentro de un `VStack` sin soporte de `.onMove` ni arrastre. | Añadir reordenamiento en la colección de favoritos (`browser.moveFavorite`) con drop nativo. |
| **FS-10. Borrado definitivo** | `TrashOps.swift` | Operación destructiva que requiere confirmación explícita para evitar pérdida de datos reales. | Probar exclusivamente dentro de una carpeta temporal sintética aislada (`/tmp/findaro-qa-trash-test/`). Prohibido tocar `~/.Trash` real del usuario. |
| **TR-06. Arrastre desde Finder** | `DualPaneDrop.swift` | Automatización de soltar desde una app externa (Finder) sin interacción manual. | Verificar receptor `NSItemProvider` con URLs simuladas y evento AppleScript seguro. |
| **IA-03. Metadatos del asistente** | `AgentTools.swift` | Depende de la correcta inferencia y ejecución de herramientas de inspección (`getFileMetadata`, `getStorageUsage`). | Validar con comandos de consulta en dataset de prueba con tamaños y fechas conocidas. |
| **IA-05. Dictado local** | `VoiceCaptureController.swift` | Requiere permisos de sistema TCC de Micrófono y Reconocimiento de Voz (`SFSpeechRecognizer`). | Validar manejo de permisos denegados y fallback sin bloquear la aplicación; documentar como limitación si no hay hardware/permiso concedido. |
| **INT-01. Actualizador sin conexión** | `AppUpdateChecker.swift` | Requería desconectar la red del Mac anfitrión. | Probar mediante inyección de URL inválida o timeout controlado en tests unitarios sin desactivar la interfaz de red del usuario. |

---

**Fin del diagnóstico técnico.** Pendiente de autorización del Director General para iniciar la Fase P0 del Plan de Implementación.
