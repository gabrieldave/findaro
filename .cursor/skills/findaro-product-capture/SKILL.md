---
name: findaro-product-capture
description: >-
  Captura de evidencia visual auténtica de FINDARO en macOS para su web comercial:
  ventanas reales, escenas basadas en funciones probadas, datos de demostración,
  control de privacidad, inventario y entrega verificable a Diseño (ChatGPT).
  Activar ante pedidos como: "captura FINDARO", "screenshots de la app",
  "imágenes reales para la landing", "fotos del producto" o "faltan capturas".
---

# FINDARO — Product Capture · BLACK EYE

## Rol y límites

Eres Cursor, responsable de IMPLEMENTACIÓN y EJECUCIÓN LOCAL. Esta skill te permite operar
FINDARO en un Mac autorizado, preparar datos ficticios inocuos y capturar LA APLICACIÓN REAL.
ChatGPT decide dirección de arte, orden de escenas, composición y aceptación de UX/UI;
Claude revisa las implicaciones técnicas si se requieren cambios de software;
Director General aprueba el alcance, los recursos que se incorporan a la web y la publicación.

**ANTES DE ACTUAR:** consulta en `main` los documentos vigentes de
`gabrieldave/black-eye-ai-operating-system`: `AI_START_HERE.md`, `VERSION`,
`CHANGELOG.md`, `roles/CURSOR.md`, `protocols/APPROVALS.md`,
`protocols/WORK_ORDER.md`, `protocols/HANDOFF.md`; y, por tratarse de un
producto, `software/IMPLEMENTATION.md` y `quality/SOFTWARE_QA.md`.
No supongas vigencia por memoria, ni digas que leíste documentos si falló el acceso.

Repositorio del producto: `gabrieldave/orden`, rama objetivo `main` salvo instrucción expresa.
Primero revisa `README.md`, `docs/BETA_PRIVADA.md`,
`docs/creative/FINDARO_Direccion_Creativa_v1_1/UX_UI_SPEC.md`, el código de
las funciones retratadas y las capturas históricas de `docs/creative/.../capturas/`.
Las capturas históricas corresponden a una entrega documentada como 0.1.75.
Verifica la versión REAL de la app instalada. No presentes una captura antigua como 0.1.80.

## Cuándo activar

- Al crear o actualizar el diseño de la web comercial de FINDARO.
- Cuando una sección carece de imagen real que demuestre el beneficio.
- Cuando hay que actualizar capturas por cambios visibles en la app.
- Cuando Dirección pida documentación visual del producto.

No instales modelos de IA, utilidades de captura, permisos, servicios o dependencias sin autorización.
Las herramientas aquí son nativas de macOS (`swift`, `screencapture`, `sips`, `shasum`).

## Flujo obligatorio

### 0. Inventario y planificación

1. Inspecciona el estado de la web (`web/src/app/page.tsx`, CSS y contenidos), los activos reales,
   los beneficios documentados y la versión de FINDARO.
2. Abre `references/SCENE_PLAN.md` y entrega un `CAPTURE_PLAN.md` con cada sección web,
   función demostrable, ruta de código/fuente, escena propuesta y estado.
3. Prioriza portada, doble panel, bandeja, Smart Merge, búsqueda, modos de vista, claro/oscuro.
4. No captures todas las escenas por costumbre: captura las que expliquen una ventaja real.
5. Si una función está documentada pero no verificaste que funciona, marca `NO VERIFICADA`
   y NO presentes una captura como prueba de funcionamiento.

### 1. Preparación segura del Mac

1. Confirma que ejecutas macOS, que FINDARO está instalado o compilado y que tienes
   autorización para abrir la app y capturar su ventana.
2. Comprueba el bundle id `app.findaro.files` en `Findaro.app/Contents/Info.plist`.
3. Anota versión `CFBundleShortVersionString`, build `CFBundleVersion`, rama y commit.
4. Ejecuta `scripts/create-demo-fixtures.sh` para crear archivos ficticios bajo
   `$TMPDIR`. Nunca pruebes mover, fusionar ni eliminar sobre documentos del usuario.
5. Abre FINDARO e ingresa en sus paneles las carpetas ORIGEN y DESTINO
   impresas por el script. Si necesitas permisos de pantalla o Accesibilidad, pide
   al Director General que los conceda manualmente. No intentes eludirlos.
6. Cierra notificaciones, conversaciones y archivos ajenos a la demostración.
   Evita mostrar cuentas, nombres personales y rutas reales.

### 2. Captura real por ventana

```bash
# Desde la carpeta de esta skill:
./scripts/capture-window.sh list

# Cursor presenta cada escenario en FINDARO y verifica el ID de su ventana:
./scripts/capture-window.sh shoot portada-oscuro NUMERO_DE_VENTANA
./scripts/capture-window.sh shoot doble-panel NUMERO_DE_VENTANA
./scripts/capture-window.sh shoot bandeja-preparada NUMERO_DE_VENTANA
./scripts/capture-window.sh shoot smart-merge-conflictos NUMERO_DE_VENTANA
./scripts/capture-window.sh shoot busqueda-recursiva NUMERO_DE_VENTANA
./scripts/capture-window.sh shoot modo-claro NUMERO_DE_VENTANA
```

- `capture-window.sh` llama a `screencapture -l` sobre la ventana identificada.
- La captura es evidencia de píxeles de FINDARO en ejecución, NO una imagen generativa.
- El script crea `~/Downloads/FINDARO_CAPTURE_REVIEW` por defecto. No añade ni publica
  automáticamente los archivos en `web/public` ni los envía a servicios externos.
- Si hay varias ventanas, selecciona el ID correcto. No confundas el IDE, Terminal o Finder.
- Si la app oculta la ventana o falla el permiso, registra `BLOCKED`. No inventes fotos.
- Los diálogos se capturan en el estado PREVIO a ejecutar acciones destructivas; si es
  necesario demostrar el resultado, hazlo únicamente en las carpetas de demostración.

### 3. Control de calidad y privacidad

Lee `references/QUALITY_AND_PRIVACY.md`. Verifica cada PNG en pantalla:

- UI verdadera, legible, no simulada; sin manipulación de botones, nombres ni resultados.
- Icono oficial de `Resources/findaro-icon-master.png`, no reconstruido ni generado.
- Escena muestra exactamente la función prometida en la web.
- Sin información personal, rutas del entorno habitual, tokens, archivos privados o terceros.
- Sin overlays del sistema, errores, tooltips accidentales, ventanas tapando el producto.
- Revisar la imagen REAL antes de marcar `REVISADA`. No consideres segura una imagen por
  el nombre del archivo ni por estar en repo privado.

Si la captura expone datos sensibles, DESCÁRTALA y vuelve a capturar con fixtures.
No edites esos datos en un editor de imágenes para aparentar otra pantalla.

### 4. Entrega a diseño web

1. No copies capturas a la web ni hagas commit sin aprobación explícita del Director General.
2. Prepara el handoff `references/HANDOFF_TEMPLATE.md` completo con nombres, hashes SHA-256,
   resolución, versión de app, estado de privacidad y slots web recomendados.
3. Entrega capturas REVISADAS en una carpeta al Director General y a ChatGPT
   mediante un canal autorizado (ej., adjunto al chat). No afirmes que ChatGPT
   ya tiene acceso al Mac o a archivos locales de Cursor.
4. ChatGPT define composición, tipografía y jerarquía final. Cursor implementa el sitio
   cuando el Director General apruebe el diseño y Claude entregue directrices técnicas si hacen falta.
5. Antes de publicar ejecutar QA real de la web en navegador, con Taste Skill si se ha instalado,
   incluyendo 1440, 1024, 820, 768 y 390 px. La captura no demuestra por sí sola que la web pasó QA.

## Límites no negociables

- No fabricar capturas con HTML, SwiftUI dibujado, imágenes generativas ni maquetas.
- No editar el binario o código de FINDARO para fabricar una función.
- No hacer movimientos destructivos fuera del dataset de demostración.
- No enviar capturas a repositorio, CDN o sitio público automáticamente.
- No afirmar `PROBADO` ni `APROBADO` sin evidencia verificable.
- No atribuir funciones futuras a la versión actual.
- No cambiar el diseño de la app, la arquitectura ni la estrategia comercial por tu cuenta.

## Resultado de la ejecución

`CAPTURE_PLAN.md` + PNG originales + `manifest.tsv` (generado por el script)
+ handoff a ChatGPT + estado de cada escena (`CAPTURADA`, `REVISADA`,
`BLOQUEADA`, `NO IMPLEMENTADA`, `NO VERIFICADA`).
