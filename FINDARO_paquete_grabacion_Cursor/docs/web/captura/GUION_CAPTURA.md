# FINDARO: guion de grabación para la landing

**Para:** Cursor (ejecución local en el Mac). **De:** Claude (CTO). **Aprueba:** Director General.
**Estado:** LISTO PARA EJECUTAR. Nada de esto se publica: el material se entrega en un ZIP y Claude lo procesa.
**Build a grabar:** la que esté instalada y aprobada por el Director; `capture.sh prep` la registra (HEAD empaqueta 0.1.88 / 94).

## 1. Por qué fallaron las capturas anteriores
1. Ventana de 2820 px en una pantalla 21:9: en la web se reduce a la mitad y el texto queda en 6 px.
2. Carpetas casi vacías (cuatro carpetas de 36 bytes): no se ve el trabajo real.
3. Pantallas en reposo: no se ve ninguna acción.

## 2. Preparación (una sola vez)

### Cuenta y privacidad
- Crear una cuenta de macOS nueva llamada **`demo`** (nombre completo «Demo»). Grabar todo desde ahí.
- En esa cuenta: sin Google Drive, Dropbox ni iCloud con datos; sin volúmenes de red. `capture.sh prep` avisa si encuentra alguno.
- Apariencia **oscura**, No molestar activado, Dock oculto, escritorio sin iconos, ninguna otra app visible.
- Instalar Findaro en `/Applications` y darle a la Terminal (o a Cursor) permisos de **Accesibilidad** y **Grabación de pantalla**.

### Pantalla 21:9 (3440×1440)
La pantalla del Director es ultrapanorámica y casi seguro trabaja a 1x (sin Retina).
- **Nunca maximizar Findaro.** Ventana de **1280×800 puntos**, centrada: `scripts/demo/capture.sh window`.
- Si el Mac es un portátil con pantalla Retina, grabar en esa pantalla: el resultado sale a 2x (2560×1600) y se ve más nítido. En ese caso, misma ventana de 1280×800 puntos.
- Si a 1280 la barra de acciones se ve partida o apretada, probar `capture.sh window 1440 900` e indicarlo en el handoff.

### Set de prueba
```bash
python3 scripts/demo/make_demo_dataset.py              # crea ~/Documents/FINDARO-Demo (≈1,7 GB, 1-2 min)
python3 scripts/demo/make_demo_dataset.py --reset      # vuelve al estado inicial entre tomas
```
Estudio fotográfico ficticio «Estudio Aurora»:
- `ORIGEN/Estudio Aurora`: Campaña-Otoño-2026 (Fotos, Selección, Video, Documentos), Clientes, Facturas, Plantillas, Entregas (ZIP y TAR) y dos archivos ocultos.
- `DESTINO/Respaldo Estudio`: copia anterior y desactualizada.
- Smart Merge en `Campaña-Otoño-2026/Documentos` da **6 nuevos, 3 iguales y 2 distintos**.
- Buscar **«contrato»** desde `Estudio Aurora` da **8 resultados**.

Barra lateral de Findaro: dejar en Favoritos solo `Estudio Aurora`, `Respaldo Estudio`, Descargas, Escritorio y Documentos.

## 3. Reglas de grabación
- **Reset del set antes de cada toma que mueve archivos** (V1, V2, V3, V4, P03, P05, P06).
- Movimientos de ratón lentos y directos. Pausa de 1 s quieto al empezar y al terminar (el video va en bucle).
- Si una toma sale mal, se repite entera; no se edita para simular nada.
- Cada archivo con el id exacto de las tablas: `capture.sh shot <id>` / `capture.sh video <id> <segundos>`.
- Antes de entregar, abrir cada PNG y cada video al 100 % y revisar barra de título, rutas, barra lateral, tooltips y contenido. Marcar en `manifest.tsv` la columna `revision_privacidad` como `OK` o anotar el problema.

## 4. Videos (lo más importante)

| ID | Seg. | Estado inicial | Acción que se graba |
|---|---|---|---|
| V1-cortar-pegar | 10 | Dos paneles (⌘⇧D). Origen: `Campaña-Otoño-2026/Selección` en vista Iconos. Destino: `Respaldo Estudio/Campaña-Otoño-2026/Selección` | Clic en una foto, ⇧+clic en otra (3 seleccionadas) → ⌘X (se atenúan y van a la bandeja) → Tab → ⌘V → aparecen en Destino |
| V2-mover-entre-paneles | 8 | Origen: `Clientes/Hotel-Marea/Fotos-habitaciones` (lista). Destino: `Respaldo Estudio/Clientes-2025` | Seleccionar 3 fotos → ⌘⇧M → aparecen en Destino y Origen se actualiza solo |
| V3-smart-merge | 12 | Origen: `Campaña-Otoño-2026`. Destino: `Respaldo Estudio/Campaña-Otoño-2026` | Arrastrar o mover `Documentos` al Destino → se abre «Fusionar carpetas» → 2 s quieto en el diálogo → «Conservar ambos» → resultado en Destino |
| V4-transferencia-verificada | 15 | Origen: `Campaña-Otoño-2026`. Destino: `Respaldo Estudio` | Copiar la carpeta `Video` al Destino → barra de progreso → mensaje final de verificación. Si dura menos de 6 s, recrear el set con `--video-mb 3000` |
| V5-busqueda | 10 | Origen: `Estudio Aurora` | ⌘4 → escribir «contrato» letra por letra → 8 resultados → clic en `anexo-contrato-marea.pdf` → Findaro lo muestra en su carpeta |
| V6-cuatro-vistas | 9 | Origen: `Campaña-Otoño-2026/Fotos`, un panel | Pulsar los botones de vista de la barra superior: Iconos → Lista → Columnas → Galería, unos 2 s en cada una |
| V7-omnibox | 7 | Origen: `Estudio Aurora` | ⌘L → escribir `~/Documents/FINDARO-Demo/ORIGEN/Estudio Aurora/Facturas` → Enter |
| V8-descomprimir | 7 | Origen: `Estudio Aurora/Entregas` | Abrir `Entrega-Aurora-v1.zip` → aparece la carpeta descomprimida |

## 5. Fotos (PNG)

| ID | Qué debe verse |
|---|---|
| P01-hero | Dos paneles. Origen: `Selección` en vista Iconos con 2 fotos seleccionadas. Destino: `Respaldo Estudio/Campaña-Otoño-2026` en lista. Bandeja con 3 elementos (copiar) |
| P02-doble-panel | Dos paneles en lista. Origen: `Clientes`. Destino: `Respaldo Estudio`. Panel Destino activo |
| P03a-seleccion / P03b-tras-cmd-x / P03c-tras-cmd-v | Los tres momentos de V1 como fotos fijas |
| P04-smart-merge | Diálogo «Fusionar carpetas» abierto (6 / 3 / 2) sin pulsar nada |
| P05-transferencia | Barra de progreso de V4 a mitad del lote |
| P06-verificacion | Mensaje final de V4 |
| P07-busqueda | 8 resultados de «contrato», el tercero seleccionado |
| P08-iconos / P09-lista / P10-columnas / P11-galeria | `Campaña-Otoño-2026/Fotos` en cada vista |
| P12-omnibox | Ruta escrita en el omnibox antes de pulsar Enter |
| P13-atajos | Ajustes › Atajos con la lista visible y el perfil «Teclado tipo Explorer» |
| P14-ocultos | `Estudio Aurora` con ⌘⇧. activo (se ven `.presets-color.xmp` y `.cache-miniaturas`) |
| P15-modo-claro | **Solo si** los paneles de archivos cambian a claro con la apariencia clara del sistema. Si siguen oscuros, no capturar y reportarlo como defecto (ver capturas 0.1.86) |

No grabar el asistente con IA salvo que el Director lo pida.

## 6. Entrega
1. `scripts/demo/capture.sh pack` → `~/Desktop/FINDARO_CAPTURA_<fecha>.zip` con `png/`, `video/` (`.mov` sin editar) y `manifest.tsv`.
2. Añadir dentro un `HANDOFF.md` con el formato de BLACK EYE (`protocols/HANDOFF.md`): build y commit, pantalla usada, tamaño de ventana, tomas hechas y no hechas, problemas encontrados (por ejemplo el modo claro) y revisión de privacidad.
3. Entregar el ZIP al Director. **No** copiar nada a `web/public`, no hacer commit de los PNG ni videos y no subirlos a ningún servicio.

Claude se encarga después de recortar, comprimir los videos (MP4/WebM de 1 a 2 MB con imagen fija de respaldo), revisar la privacidad otra vez y montarlos en la web.
