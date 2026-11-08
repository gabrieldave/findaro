# Encargo para Claude: módulo comparativo FINDARO

## Objetivo
Integrar en `https://findaro.iareal.net/findaro-landing.html` una sección comercial basada en el prototipo `index.html` del paquete. El objetivo es justificar el precio premium de FINDARO con una comparación que ayude a decidir, no desacreditar a competidores.

## Ubicación
Entre las demostraciones reales de las funciones (doble panel, Smart Merge, IA local) y la oferta/precio final. No duplicar el hero ni añadir una segunda página desconectada de la compra. La demo incluye un encabezado de marca `brandbar` que debe eliminarse al insertar el módulo en la landing.

## Enfoque visual
- Identidad oficial: #0B1220, #141F32, azul #2563EB, texto claro. Violet reservada para IA.
- Encabezado 34-56 px, cuerpo 15-17 px, tarjetas de valor compactas.
- Comparador interactivo: selector de competidor, filtros, 3 columnas (función/FINDARO/competidor), matriz ampliable.
- Responsive: escritorio, tableta y móvil (320,390,768,820,1024,1440).
- Los beneficios mejor sustentados: Smart Merge con previa; SHA-256 en transferencias; rollback; IA local Ollama; voz push-to-talk; aprobación de operaciones; ⌘X y bandeja; doble panel.
- Reconocer fortalezas rivales en servicios remotos/sincronización; no convertir los valores sin verificar en indicadores de ausencia.
- Incluir acceso a metodología y fuentes visibles para afirmaciones contrastadas, fecha de corte y versiones verificadas.

## Implementación
- Primero identificar si la ruta pública `findaro-landing.html` es HTML estático o la entrega del proyecto Next.js. Si es estática, integrar el módulo HTML/CSS/JS sin reescribir todo el sitio. Si se renderiza desde Next.js, convertirlo en componente React/TSX client-side. Sin duplicar interfaces ni instalar bibliotecas pagadas.
- Mover dataset curado a módulo de datos o JSON importado, renderizar filas con `map`, no inyectar HTML sin sanitizar.
- Verificar la compra en `/comprar` y precio 59/99 vigentes antes de publicar. No prometer prueba de 5/14 días mientras el sistema de licencias no la implemente.
- Añadir accesibilidad: foco visible, nombre accesible del selector, estado de filtros, reducción de movimiento, lectura de estados sin depender solo del color.
- La landing debe ser una pieza continua con el diseño existente, no un layout genérico.

## Reglas de evidencia
- FINDARO: inventario entregado por Dirección, aprox. versión 0.1.94; confirmar con build actual. La existencia en inventario no reemplaza prueba de UI.
- Comparadores: los datos de este prototipo proceden de una matriz documental previa. Revalidar en fichas oficiales y documentar URLs por característica antes de ponerlo público.
- `Sin confirmar` significa sin evidencia suficiente, NO ausencia.
- `Similar` indica una función relacionada, NO igual.
- Evitar cifras inventadas como “3 veces más rápido”, “más seguro que todos”, “primero con IA”. No inventar reseñas/testimonios.
- Si la comparación no se verificó completamente, publica un módulo de los beneficios de FINDARO sin columnas de competidores hasta completar validación.

## Autoridad
BLACK EYE 1.3.1: Claude supervisa arquitectura; Cursor implementa y prueba; ChatGPT dirige producto/diseño; el CEO aprueba publicación G4. No publicar, no editar producción ni hacer commits sin autorización.

## Pruebas
- Ejecutar las pruebas de Taste Skill y el catálogo de estilo del repo local cuando estén disponibles.
- Test visual real y accesibilidad en 1440x900, 1024x768, 820x1180, 768x1024, 390x844 y 320x740.
- Comprobar selector, filtros, expansión, CTA, foco, larga lista de 50 y sin scroll horizontal no intencional.
- Reportar pruebas realizadas y capturas. No inventar un PASS.

## Corrección V1.1 de filtros
- Las pestañas de categorías deben permanecer habilitadas también cuando el usuario despliega «Ver las 50 características». Pulsar una pestaña desde vista completa debe volver automáticamente a la selección de esa categoría.
- El botón activo es azul y los demás tienen contraste, hover y foco visibles: gris no significa deshabilitado.
- Corrección de integridad documental: las filas 46-50 de «Donde otros destacan» no están documentadas en el inventario FINDARO y deben marcarse N/D, no «Sí». No representar N/D como ausencia comprobada.
- Probar estas transiciones con ratón y teclado en la landing integrada, no solo en archivo local.


## Ajustes solicitados por Dirección, versión 1.2
- H2 literal: «¿Cómo se compara FINDARO con la competencia?»
- Filtros navegables en cualquier estado, incluso tras abrir «Ver las 50 características».
- «Sin confirmar»: mostrar etiqueta roja e incluir nota explícita indicando que desconocido NO significa ausente.
- No sustituir datos N/D por «No lo tiene» sin evidencia verificable individual.
- Cinco funciones de conectividad / sincronización / compresión / renombrado avanzado / terminal no están documentadas en FINDARO. No atribuirlas al producto.
- «Lo esencial» debe centrarse en los beneficios reales del producto, no características de rivales.
