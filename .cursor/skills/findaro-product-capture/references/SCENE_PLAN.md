# FINDARO — Plan de capturas sugerido

Cada escena debe justificar una sección de la landing con evidencia de la versión instalada.
No se requiere capturar escenas sin relevancia comercial o sin función comprobada.

| Prioridad | ID de escena | Qué mostrar | Acción segura y requisitos | Slot web sugerido |
|---|---|---|---|---|
| P0 | `portada-oscuro` | Ventana principal amplia, sidebar y contenido | App en oscuro, carpeta demo, sin datos privados | Hero |
| P0 | `doble-panel` | Dos carpetas distintas visibles simultáneamente | ORIGEN y DESTINO del dataset | Doble panel |
| P0 | `bandeja-preparada` | Archivos ficticios seleccionados y bandeja con elementos | Copiar/cortar demo, antes de ejecución | Transferencias |
| P1 | `smart-merge-conflictos` | Vista previa con nuevos, iguales y conflictos | Demo con archivo `conflicto.txt` diferente por lado | Smart Merge |
| P1 | `busqueda-recursiva` | Panel y resultados reales del dataset | Buscar `plan` o `resumen` y comprobar resultados | Búsqueda |
| P1 | `modo-claro` | El mismo dataset en apariencia clara | Cambiar apariencia del SO/app, confirmar ventana | Apariencia |
| P2 | `vista-iconos` | Cuadrícula de iconos nativa | Cambiar modo de vista sin salir del dataset | Visualización |
| P2 | `vista-columnas` | Navegación por columnas | Carpetas demo | Visualización |
| P2 | `vista-galeria` | Vista galería con archivo de prueba | Usar archivo reconocido, sin multimedia privada | Visualización |
| P2 | `asistente-local` | Panel real con IA opcional DESACTIVADA o una tarea de reglas verificada | No simular chat ni resultados; no activar Ollama sin permiso | Asistente local |
| P2 | `vista-rapida` | Vista previa de archivo de prueba | Texto demo y Quick Look si está implementado | Previsualización |

## Guía de composición

- Portada: ventana real de FINDARO ocupa gran parte del espacio; mostrar barra, sidebar y archivos demo.
- Doble panel: las dos rutas deben poder distinguirse, con el foco activo visible.
- Bandeja: mostrar elementos en cola, no una bandeja vacía si se promete productividad.
- Smart Merge: mostrar el diálogo real y sus categorías; no asegurar éxito del merge por ver un diálogo.
- Búsqueda: emplear archivos demo preparados y resultados comprobables.
- Apariencia: la foto de modo claro debe corresponder a la app real, no un filtro sobre la oscura.
- No recortar controles importantes dentro del archivo original; la web puede ajustar su presentación
  manteniendo intacta la captura fuente.

## Fuente de comportamiento

Verificar en la versión de trabajo: `BrowserModel.swift`, `ContentView.swift`,
`BrowserLayoutViews.swift`, `DropShelfView.swift`, `MergePreviewSheet.swift`,
`RecursiveSearchPanel.swift`, `FolderMerge.swift`, `TransferQueue.swift`,
`QuickLookController.swift`, `AssistantPanel.swift` y los tests asociados.
La presencia del archivo no equivale a ejecución correcta.

## Mínimo de aceptación

4 escenas P0/P1 revisadas como mínimo, excepto si no están implementadas o se
encuentran bloqueadas. Registrar el bloqueo con evidencia, no sustituir la escena
por una simulación. Incluir la versión exacta instalada.
