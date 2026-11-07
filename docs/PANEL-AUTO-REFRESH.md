# Actualización automática de paneles (FSEvents)

## Entorno de validación

- macOS **27.0.1**
- Xcode **27.2** / Swift **6.4**
- Deployment Target del paquete: **macOS 15** (sin rebajar)
- CI: runner GitHub Actions `xcode-27` (macOS 27 + Xcode 27)

## Comportamiento

`FolderWatcher` observa cada carpeta visible con FSEvents (`FileEvents` + `NoDefer` + `WatchRoot`).

| Modo | Observadores |
|---|---|
| Un panel | 1 watcher sobre `currentPath` |
| Doble panel, carpetas distintas | 2 watchers independientes |
| Doble panel, misma carpeta | 1 watcher (primario); el reload sincroniza ambas listas |

Notificaciones:

1. **Leading** (~50 ms): el primer evento del burst muestra archivos nuevos al instante.
2. **Trailing** (~180 ms): consolida renombres / fin de descarga sin parpadeo.
3. **Max interval** (~700 ms): durante escrituras continuas fuerza refrescos periódicos.

Tras un evento:

- Se recarga el listado **sin salir de la carpeta**.
- Se conserva la selección (primaria y secundaria) cuando los ids siguen existiendo.
- No se relanzan walks de tamaño de carpetas en cada tick FSEvents (evita flicker).

## Escenarios cubiertos por tests

- Archivo nuevo en carpeta observada
- Patrón Chrome (`.crdownload` → nombre final)
- Rename y delete externos
- Burst de escritura continua
- Rewatch idempotente de la misma ruta

## Manual (UI)

1. Abrir Descargas en un panel → descargar desde el navegador → debe aparecer solo.
2. Doble panel: Descargas a la izquierda / Escritorio a la derecha → descargar en cada una.
3. Copiar/mover entre paneles → origen y destino se actualizan.
4. Renombrar/borrar desde Finder → Ordena refleja el cambio.
5. Alternar doble panel on/off → no deben quedar watchers huérfanos.
6. Clic en el vacío de un panel → ese panel queda **activo** al instante (sin botón Activar).

## UX relacionada (Top 5)

- Omnibox: ⌘L o doble clic en breadcrumbs.
- Explorer: Ajustes → «Teclado tipo Explorer» (Enter abre / F2 renombra).
- Cut visual: ⌘X atenúa y tacha el archivo hasta pegar.
- Ocultos: ⌘⇧. · Vista plana: menú Ir / Ajustes.
- TransferQueue: barra de progreso + verify de tamaño en moves/copias entre paneles.
