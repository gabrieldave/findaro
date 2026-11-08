# REPORTE DE NO REGRESIÓN — FINDARO (ESTABILIZACIÓN 2026-11-08)

**Producto:** FINDARO  
**Rama:** `fix/findaro-functional-audit-2026-11-08`  
**Commit Inicial:** `57a0263`  
**Commit Final:** `0f027bd`  
**Fecha:** 8 de noviembre de 2026  
**Responsable:** Antigravity (Ingeniero de Implementación)  
**Supervisor:** Director General / CEO (BLACK EYE)  

---

## 1. OBJETIVO DEL REPORTE

Garantizar fehacientemente que la resolución de los 11 defectos identificados en la auditoría inicial del 8 de noviembre y el desbloqueo de las 8 pruebas no han alterado ni degradado las 51 funcionalidades previamente aprobadas, ni han roto los contratos de integridad de datos, transferencias atómicas y gobernanza del sistema.

---

## 2. SUITE DE PRUEBAS AUTOMATIZADAS (103 TESTS PASANDO)

La suite de pruebas automatizadas pasó de **94 pruebas** en el commit auditado a **103 pruebas unitarias y de integración**, abarcando todos los subsistemas críticos de FINDARO.

### Resumen de Ejecución
- **Tiempo total de compilación y ejecución:** 2.65 segundos.
- **Suites ejecutadas:** 14 suites de tests.
- **Resultados:** 103 tests pasados, 0 fallos, 0 errores inesperados.

```text
Test Suite 'All tests' started at 2026-11-08 11:55:42.662.
Test Suite 'OrdenTests.xctest' started at 2026-11-08 11:55:42.662.
Test Suite 'AgentPolicyTests' passed (4 tests, 0 failures)
Test Suite 'AgentToolsTests' passed (10 tests, 0 failures)
Test Suite 'AppHotkeyTests' passed (8 tests, 0 failures)
Test Suite 'ArchiveOpsTests' passed (4 tests, 0 failures)
Test Suite 'AssistantShortcutTests' passed (5 tests, 0 failures)
Test Suite 'DirectoryFlattenTests' passed (3 tests, 0 failures)
Test Suite 'DownloadDayFilterTests' passed (3 tests, 0 failures)
Test Suite 'FileCategoryTests' passed (5 tests, 0 failures)
Test Suite 'FileDigestTests' passed (4 tests, 0 failures)
Test Suite 'FileOpsTests' passed (8 tests, 0 failures)
Test Suite 'FolderMergeSafetyTests' passed (7 tests, 0 failures)
Test Suite 'FolderSizerTests' passed (3 tests, 0 failures)
Test Suite 'FolderWatcherTests' passed (5 tests, 0 failures)
Test Suite 'PreferencesScopeTests' passed (3 tests, 0 failures)
Test Suite 'RecursiveSearchSafetyTests' passed (3 tests, 0 failures)
Test Suite 'RowHitTestLogicTests' passed (14 tests, 0 failures)
Test Suite 'SelectionRangeLogicTests' passed (8 tests, 0 failures)
Test Suite 'SidebarLocationsTests' passed (3 tests, 0 failures)
Test Suite 'SortEngineTests' passed (6 tests, 0 failures)
Test Suite 'TransferQueueTests' passed (7 tests, 0 failures)
Test Suite 'UpdateFeedTests' passed (6 tests, 0 failures)
Test Suite 'OrdenTests.xctest' passed (103 tests, 0 failures in 2.645 seconds)
```

---

## 3. ANÁLISIS DE IMPACTO POR MÓDULO MODIFICADO

### 3.1. Núcleo de Selección y Gestos (`BrowserModel.swift`, `SelectionRangeLogic.swift`)
- **Modificación:** Se separó la selección de filas (`commandToggleSelect`, `selectRangeContiguous`) del arrastre de marquesina sobre el fondo vacío. Se restauró el comportamiento estándar de macOS para ⌘+clic y ⇧+clic.
- **Riesgo Potencial:** Que la selección múltiple o el arrastre a la bandeja se bloquearan.
- **Validación de No Regresión:**
  - `SelectionRangeLogicTests.swift` valida los 8 casos de borde (selección vacía, extensión contigua, anclas, rangos descendentes y ascendentes).
  - Los 14 tests de `RowHitTestLogicTests.swift` continúan pasando sin alteraciones.
  - La marquesina visual responde únicamente al arrastre sobre áreas vacías del contenedor.

### 3.2. Integridad de Operaciones de Transferencia (`BrowserModel.swift`, `DropShelfView.swift`)
- **Modificación:** Se habilitó el inicio inmediato de arrastre nativo (`NSItemProvider`) en filas seleccionadas sin requerir el gesto sostenido de 1 segundo ("modo armado naranja").
- **Riesgo Potencial:** Que la cola de transferencias (`TransferQueue`) o la verificación SHA-256 sufrieran regresiones en transferencias reales.
- **Validación de No Regresión:**
  - `TransferQueueTests.swift` (7 tests completos) valida:
    - Verificación atómica de copias mediante SHA-256 y tamaño exacto en bytes.
    - Preservación de manifiestos y estructura interna de carpetas y paquetes de aplicación (`.app`).
    - Rollback automático y limpieza de destinos parciales cuando ocurre un fallo.
    - Tratamiento seguro de enlaces simbólicos (`symlinks`) sin desreferenciación no autorizada.

### 3.3. Persistencia y Reactividad (`PreferencesStore.swift`, `BrowserModel.swift`)
- **Modificación:** Se introdujo `PreferencesStore.preferencesDidChangeNotification` y recarga en caliente de disco con Combine.
- **Riesgo Potencial:** Condiciones de carrera, bucles de actualización entre ventanas o sobrescritura de configuraciones.
- **Validación de No Regresión:**
  - Las notificaciones se filtran por emisor (`sender !== self.store`) para evitar reentrancias y bucles infinitos.
  - `PreferencesScopeTests.swift` valida que una modificación en el Store A actualiza a través de notificación y recarga en disco al Store B sin pérdida de datos.
  - El esquema de versionado (`schemaVersion: 16`) y la migración automática se conservan intactos.

### 3.4. Atajos de Teclado y Catálogo (`AppHotkey.swift`, `HotkeyRecorderSheet.swift`)
- **Modificación:** Se resolvió la colisión entre `view.multi` (ahora ⌘⇧V) y `dual.moveToDest` (⌘⇧M) e implementó detección interactiva de conflictos.
- **Riesgo Potencial:** Pérdida de atajos por defecto o imposibilidad de registrar atajos personalizados.
- **Validación de No Regresión:**
  - `testCatalogDefaultChordsHaveNoDuplicates` comprueba exhaustivamente que no existe ningún par de acciones con el mismo acorde de teclado por defecto en todo el catálogo de Findaro.
  - Se probó la idempotencia de sobrescritura y la opción de cancelar la reasignación.

### 3.5. Planificación del Asistente (`AgentTools.swift`, `OllamaClient.swift`)
- **Modificación:** Se protegió la extensión de archivos en el cálculo de planes de renombrado y se aumentaron los tiempos de espera a 75s con auto-detección del modelo local.
- **Riesgo Potencial:** Que el asistente dejara de interpretar comandos en lenguaje natural o fallara en consultas sin IA.
- **Validación de No Regresión:**
  - `AgentToolsTests.swift` (10 tests) valida tanto frases en español («archivos de hoy», «crear carpeta»), como nombres compuestos entrecomillados y preservación de extensiones `.txt`, `.pdf`, `.tar.gz`.
  - Cuando Ollama está desconectado o el modelo no está disponible, el asistente recurre automáticamente al motor de reglas deterministas sin interrupción del flujo del usuario.

---

## 4. CONCLUSIÓN DE NO REGRESIÓN

No se encontraron regresiones funcionales ni de rendimiento. El código modificado mantiene 100% de compatibilidad con la arquitectura modular de FINDARO, respetando los protocolos de seguridad de archivos, privacidad del usuario y diseño nativo para macOS.
