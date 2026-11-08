# IMPLEMENTATION_PLAN — RECUPERACIÓN Y ESTABILIZACIÓN DE FINDARO

**Versión objetivo:** 0.1.103-stabilized (Build 110)  
**Rama de trabajo:** `fix/findaro-functional-audit-2026-11-08`  
**Referencia base:** Commit `57a0263`  
**Autor:** Antigravity (Ingeniero macOS Senior / Modo Propuesta)  
**Aprobación requerida:** Director General / CEO (Puertas G1 y G2)  

---

## 1. Matriz de Diagnóstico y Plan de Corrección

| ID | Causa Confirmada | Archivo y Función | Severidad | Solución Propuesta | Riesgo de Regresión | Pruebas Necesarias |
|---|---|---|---|---|---|---|
| **IA-02** | `extractAfter` divide el texto en `.` (`split`), eliminando extensiones como `.txt` en el plan. | `Sources/OrdenCore/AgentTools.swift` (`extractAfter`, `extractQuoted`) | **P0 (Alta)** | Respetar extensiones en nombres de archivos; recortar únicamente puntuación final de oración (p. ej. punto final de frase si no forma parte de una extensión válida de 1 a 5 caracteres). Validar sufijos y nombres compuestos (`.tar.gz`). | Bajo. Podría afectar comandos que terminen en punto sintáctico. | Tests unitarios con cadenas: `QA-renombrado.txt`, `archivo.tar.gz`, sin extensión, y con comillas `«...»`. |
| **SEL-02** | `commandRangeSelectForMove` forzaba selección de rango en vez de disyuntiva; `FileDragArmMonitor` consume clics con ⌘; desincronización de ancla en flechas. | `Sources/OrdenApp/FileDragArmMonitor.swift`, `Sources/OrdenApp/BrowserModel.swift` (`clickSelect`, `commandRangeSelectForMove`, `selectRange`, `toggleSelection`) | **P0 (Alta)** | Restaurar comportamiento nativo de macOS: ⌘+clic alterna selección individual (`toggleSelection`); ⇧+clic y ⇧+flechas extienden rango desde el ancla; arrastrar sin ⌘ inicia drag nativo si la fila está seleccionada. | Medio. Debe preservarse la compatibilidad con la bandeja (Dropover/DropShelf) y el modo naranja explícito si se conserva. | Tests de selección unitarios (`BrowserModel`) y pruebas funcionales de clic, ⌘+clic y ⇧+flecha en dataset de prueba. |
| **TR-04** | El arrastre de archivos entre paneles exigía armar el "modo naranja" previamente; arrastrar filas seleccionadas abría selección marquesina en lugar de iniciar sesión nativa de arrastre. | `Sources/OrdenApp/BrowserLayoutViews.swift` (`marqueeGesture`), `Sources/OrdenApp/FolderDragBridge.swift` | **P0 (Alta)** | Permitir inicio de `FolderDragBridge.startDrag` directo cuando el usuario arrastra un elemento seleccionado en el panel activo; reservar la marquesina para zonas vacías o cuando no se inicia el gesto sobre un archivo seleccionado. | Medio. Podría interferir con la selección de marquesina en listas densas si el umbral no es preciso. | Prueba de transferencia interactiva entre paneles Origen y Destino; verificación de integridad SHA-256 de archivos movidos/copiados. |
| **IA-06** | `settingsBrowser` (Ajustes) y cada pestaña/ventana tienen instancias independientes de `PreferencesStore` sin bus de notificación entre ellas. Cambios en memoria pisan el disco. | `Sources/OrdenCore/PreferencesStore.swift`, `Sources/OrdenApp/BrowserModel.swift` (`persistAssistantShortcuts`, `init`) | **P1 (Media-Alta)** | Publicar `NotificationCenter` (`.ordenPreferencesDidChange`) o Combine subject cada vez que `store.update` escriba cambios; hacer que todas las instancias de `BrowserModel` escuchen y sincronicen su estado en memoria (`assistantShortcuts`, hotkeys, reglas). | Bajo. Centraliza la reactividad y elimina inconsistencias entre ventanas. | Pruebas de sincronización multiventana: editar en Ajustes y verificar recuento y títulos en la ventana de navegación sin reiniciar. |
| **BUS-08** | Misma causa raíz arquitectónica que IA-06: ajustes de filtros y reglas modificados en la ventana de Ajustes no son recargados por la sesión activa de exploración. | `Sources/OrdenCore/PreferencesStore.swift`, `Sources/OrdenApp/BrowserModel.swift` | **P1 (Media-Alta)** | Solución centralizada idéntica a IA-06. La recarga automática de preferencias en el modelo activo actualiza inmediatamente los filtros visibles y el orden. | Bajo. | Pruebas de edición de filtros en Ajustes y comprobación inmediata tras navegación. |
| **ENV-06** | `HotkeyRecorderSheet` no valida colisiones con otros atajos existentes antes de guardar. Catálogo tiene conflicto de fábrica (⌘⇧M duplicado). | `Sources/OrdenApp/HotkeyRecorderSheet.swift`, `Sources/OrdenCore/AppHotkey.swift`, `Sources/OrdenApp/BrowserModel.swift` | **P1 (Media)** | Corregir la colisión de fábrica en `AppHotkeyCatalog` (reasignar `dual.moveToDest` o `view.multi`); en `HotkeyRecorderSheet`, detectar si la combinación ya existe, advertir al usuario qué acción está asignada, y requerir confirmación antes de reasignar. Conservar botón de "Restablecer a valores de fábrica". | Bajo. | Tests unitarios de unicidad de atajos en catálogo; test de detección de colisiones. |
| **IA-04** | `OllamaClient` tiene codificado por defecto `qwen2.5:3b`, no persiste el modelo detectado (`qwen3.5:9b`), y no traduce de forma clara códigos HTTP de error como 501 o 404. | `Sources/OrdenApp/OllamaClient.swift`, `Sources/OrdenCore/PreferencesStore.swift` | **P2 (Media)** | Al detectar modelos en `probe()`, si el modelo preferido no está instalado y hay otros disponibles, sincronizar la preferencia con `setOllamaModel`; mapear códigos HTTP con mensajes descriptivos; asegurar que el fallback a reglas locales sea suave y no bloquee el hilo UI. | Bajo. No altera el backend ni descarga modelos no autorizados. | Tests de `OllamaClient` con modelo local activo `qwen3.5:9b` y prueba de respuesta JSON válida. |
| **ENV-04** | `BrowserWindowSession` carece de funciones de reordenamiento de pestañas; `BrowserTabBar` no implementa `.onDrag` ni `.onDrop` en los chips de pestaña. | `Sources/OrdenApp/BrowserWindowSession.swift` | **P2 (Media)** | Implementar `moveTab(fromOffsets:toOffset:)` y `reorderTab(sourceID:targetID:)` en `BrowserWindowSession`. Añadir soporte de arrastre y reubicación en `BrowserTabBar`. | Bajo. Cada pestaña conserva su propio `BrowserModel` y estado de navegación. | Tests unitarios de reordenamiento de colección de pestañas; verificación manual en interfaz. |
| **ENV-09** | Falta `CommandGroup(replacing: .help)` en el menú de la aplicación, dejando que macOS despliegue el error de Help Book no disponible. | `Sources/OrdenApp/OrdenApp.swift` (`FindaroCommands`), nueva vista o modal `HelpGuideView`. | **P2 (Baja-Media)** | Sustituir `.help` con un comando "Ayuda de Findaro" que despliegue una ventana/hoja modal integrada con la guía de atajos, paneles y funciones existentes. | Ninguno. | Verificación de apertura del menú Ayuda sin diálogo de error de macOS. |
| **BUS-03** | Ambigüedad visual: botón «En todas partes» con icono de globo en barra de filtros aplica regla de orden `.downloads`, no búsqueda global. | `Sources/OrdenApp/ContentView.swift` (línea 511) | **P2 (Baja)** | Modificar la etiqueta y tooltip para reflejar su función real ("Aplicar orden a todas las carpetas"), retirando el icono confuso de búsqueda global o moviéndolo a la sección de orden. Dejar la búsqueda global Spotlight como propuesta de ampliación futura. | Ninguno en código funcional; alta mejora de claridad para el usuario. | Verificación visual de etiquetas y consistencia del menú de orden. |
| **TR-13** | Procedimiento de QA y captura (`capture.sh`) grababa sin comprobar si la aplicación estaba en un entorno de pruebas aislado, mostrando rutas privadas del usuario. | `FINDARO_paquete_grabacion_Cursor/scripts/demo/capture.sh` | **P2 (Procedimental)** | Actualizar `capture.sh` para crear y navegar automáticamente a un dataset ficticio (`/tmp/FINDARO-QA-Sandbox` o `$HOME/Documents/FINDARO-Demo`), abortando si la ruta activa contiene datos personales o volúmenes no autorizados. | Ninguno sobre la app comercial. | Ejecución de `capture.sh prep` y validación de anonimato en capturas de prueba. |

---

## 2. Etapas de Ejecución por Prioridad

### Etapa P0: Integridad, Renombrado, Selección y Transferencias
1. **P0.1: Corrección de Renombrado en Asistente (`IA-02`)**
   - Ajustar `extractAfter` y `extractQuoted` en `AgentTools.swift`.
   - Añadir tests unitarios en `AgentToolsTests.swift` validando: extensiones simples (`.txt`), compuestas (`.tar.gz`), nombres con puntos intermedios (`version.1.0.txt`), y comandos con puntuación final.
2. **P0.2: Corrección de Selección Avanzada (`SEL-02`)**
   - Corregir `clickSelect` y `commandRangeSelectForMove` en `BrowserModel.swift` para que ⌘+clic sea selección aditiva disyuntiva estándar de macOS.
   - Ajustar `FileDragArmMonitor.swift` para no deglutir clics que deban ser procesados por SwiftUI.
   - Verificar estabilidad del ancla (`selectionAnchorID`) con `⇧+clic` y `⇧+flechas`.
3. **P0.3: Arrastre Nativo entre Paneles (`TR-04`)**
   - Habilitar inicio de arrastre nativo en `BrowserLayoutViews.swift` cuando el puntero inicia arrastre sobre una fila seleccionada.
   - Verificar recepción y copia/movimiento en `DualPaneDrop.swift`.

### Etapa P1: Persistencia, Atajos y Sincronización Centralizada
1. **P1.1: Sincronización Reactiva de Preferencias (`IA-06` / `BUS-08`)**
   - Implementar notificación de actualización en `PreferencesStore.update`.
   - Suscribir `BrowserModel` para actualizar automáticamente `assistantShortcuts`, reglas y filtros cuando ocurra una modificación en otra ventana o en `SettingsView`.
2. **P1.2: Gestión de Conflictos en Atajos de Teclado (`ENV-06`)**
   - Resolver conflicto nativo en `AppHotkeyCatalog` (⌘⇧M).
   - Implementar validación de conflicto en `HotkeyRecorderSheet.swift` antes de guardar, mostrando mensaje descriptivo de la acción colisionante.
   - Añadir tests unitarios en `AppHotkeyTests.swift`.

### Etapa P2: Ollama, Pestañas, Menú Ayuda y Claridad Visual
1. **P2.1: Estabilización de Cliente Ollama (`IA-04`)**
   - Sincronizar modelo detectado activo (`qwen3.5:9b`) en preferencias al inicializar.
   - Mejorar informe de errores HTTP (`404` vs `501` vs timeout) y asegurar continuidad con reglas locales.
2. **P2.2: Reordenamiento de Pestañas (`ENV-04`)**
   - Implementar mutación y reordenamiento en `BrowserWindowSession.swift`.
   - Habilitar interacción de arrastre en `BrowserTabBar`.
3. **P2.3: Menú y Ventana de Ayuda Integrada (`ENV-09`)**
   - Añadir `CommandGroup(replacing: .help)` en `OrdenApp.swift`.
   - Crear diálogo/panel de ayuda con mapa de atajos y guía de uso.
4. **P2.4: Claridad en Barra de Filtros y Búsqueda (`BUS-03`)**
   - Modificar etiqueta de «En todas partes» a «Fijar orden en todas las carpetas».
5. **P2.5: Procedimiento Seguro de Capturas (`TR-13`)**
   - Blindar `capture.sh` para operar exclusivamente en entorno ficticio aislado.

### Etapa P3: Desbloqueo de Pruebas y Auditoría de Regresión
1. **Desbloqueo de las 8 pruebas originalmente bloqueadas:**
   - `ENV-07`: Verificación de atajo global `⌃⌥O` con ventana Findaro en segundo plano.
   - `ENV-08`: Verificación de apariencia Clara / Oscura sin tocar el sistema.
   - `NAV-07`: Implementar reordenamiento de favoritos en sidebar y verificar.
   - `FS-10`: Verificación de borrado definitivo en carpeta temporal sintética `/tmp/findaro-qa-trash-test/`.
   - `TR-06`: Verificación de drop desde Finder simulado.
   - `IA-03`: Verificación de consultas de metadatos del asistente.
   - `IA-05`: Verificación del ciclo de captura de voz y fallback ante denegación de micrófono.
   - `INT-01`: Verificación de actualizador sin conexión mediante simulación en tests unitarios.
2. **Auditoría completa de las 51 pruebas aprobadas** para certificar cero regresiones.

---

## 3. Política de Control y Entregables Finales

1. **Control de Modificaciones:** No se modificará ningún archivo de código fuente de la aplicación hasta recibir la autorización expresa del Director General sobre este plan.
2. **Commits atómicos:** Cada paso se registrará en un commit independiente con mensaje convencional (p. ej. `fix(agent): preserve file extension in rename plan (IA-02)`).
3. **Compilación y verificación obligatoria:** Cada commit irá precedido de compilación limpia y paso del 100% de la suite de pruebas unitarias (`swift test`).
4. **Entregables:**
   - `TECHNICAL_DIAGNOSIS.md` (completado).
   - `IMPLEMENTATION_PLAN.md` (este documento).
   - `QA_RESULTS.md` (a completar tras ejecución).
   - `REGRESSION_REPORT.md` (a completar tras auditoría de no-regresión).
   - `HANDOFF.md` (transferencia formal según formato corporativo BLACK EYE).

---

**Solicitud de autorización:** Presentado al Director General para aprobación de las etapas P0, P1, P2 y P3.
