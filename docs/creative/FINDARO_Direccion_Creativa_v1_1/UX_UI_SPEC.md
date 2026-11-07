# FINDARO — especificación UX/UI v1.1

## Objetivo
Elevar la interfaz existente a un explorador premium para macOS sin reescribir ni eliminar capacidades. El rediseño debe mejorar jerarquía, legibilidad, claridad de operaciones y consistencia.

## Estructura de ventana
1. Sidebar: marca compacta, Favoritos, Ubicaciones y etiquetas. Ancho orientativo 190–220 pt.
2. Toolbar: navegación, vistas, ruta/omnibox y búsqueda.
3. Barra contextual: filtros, orden y acciones agrupadas por frecuencia.
4. Área principal: tabla/lista con nombre, fecha, tamaño y tipo.
5. Doble panel: rutas visibles en ambos lados, foco activo evidente y transferencia direccional inequívoca.
6. Bandeja inferior: conservar función, reducir ruido y mostrar conteo/destino/acciones.
7. Barra de estado: selección, elementos y tamaño.

## Jerarquía
- Primarias: Nueva carpeta, Copiar, Mover según contexto.
- Secundarias: Renombrar, Eliminar, Compartir.
- Avanzadas: Smart Merge, comparar, rutas, IA, ocultos, flatten.
- Acciones destructivas separadas y confirmadas según la política actual.

## Estados obligatorios
Normal, hover, pressed, focused, disabled, selección simple/múltiple, vacío, carga, error, permiso denegado, transferencia en cola/en curso/pausada/completada/fallida/rollback, panel activo/inactivo.

## Iconografía
- En controles internos de la aplicación, utilizar SF Symbols nativos con semántica correcta.
- No usar emojis, iconos de familias mezcladas ni ilustraciones decorativas como controles.
- Mantener texto en acciones críticas; no sustituir acciones importantes por símbolos ambiguos.
- No generar iconos mediante código. Los recursos de marca/marketing se entregan como PNG generado.

## Tipografía
SF Pro nativa. SF Mono solo para rutas, hashes o datos técnicos.

## Accesibilidad
Todo control debe poder usarse con teclado; focus visible; tooltips para iconos sin texto; no depender solo del color; respetar Reduce Motion y apariencia clara/oscura.

## No hacer
- No usar blur/glass en todas las superficies.
- No convertir cada botón en una cápsula brillante.
- No añadir glow persistente.
- No reducir hit targets por estética.
- No cambiar lógica FSEvents, TransferQueue, FileOps, Smart Merge, seguridad, Ollama o atajos durante el rediseño.
