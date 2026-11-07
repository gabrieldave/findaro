# Ordena — quejas reales del Finder (y de la competencia)

Fuente: investigación / reseñas de usuarios reales (Finder nativo + QSpace, Bloom, ForkLift, Path Finder, etc.).  
Uso: copy de landing, ads, App Store, demos. **No inventar “somos los primeros con IA”.**

Actualizado con el estado del producto Ordena (explorador nativo Swift).

---

## 1. De qué se quejan del Finder (copy listo)

### Fricción diaria

| Queja real | Ángulo de marketing | Estado en Ordena |
|---|---|---|
| No hay barra de direcciones editable; hay que usar ⌘⇧G | “Pega la ruta y ve. Sin rituales.” | Path bar / breadcrumbs + Ir a carpeta (⌘3) |
| No se puede cortar con ⌘X | “Cortar y pegar archivos como en Windows.” | ⌘X → bandeja (mover) · ⌘V suelta |
| Enter renombra en vez de abrir | “Elige perfil Explorer: Enter abre.” | Perfil teclado (roadmap / Settings) |
| No crear archivo nuevo desde clic derecho con facilidad | “Nueva carpeta a un clic / ⇧⌘N.” | Nueva carpeta en toolbar y menú |
| Columnas cortan nombres largos | “Nombres legibles; ruta bajo el nombre si la quieres.” | Toggle mostrar/ocultar rutas |

### Fallas graves que la gente menciona

| Queja real | Ángulo de marketing | Estado en Ordena |
|---|---|---|
| Spotlight no encuentra partes de palabra / iCloud | “Búsqueda propia en disco, sin depender solo de Spotlight.” | ⌘4 por nombre (parcial) ya; IA local = contenido + frases (roadmap) |
| Al mover carpeta sobre otra: Reemplazar borra todo | “Smart Merge: ves qué es nuevo, igual o conflicto antes de tocar nada.” | Preview de fusión (roadmap / en curso) |
| SMB/NAS lento, archivos grises, .DS_Store por todos lados | “Preferencias en la app, no .DS_Store; listados sin congelar la UI.” | Prefs propias ya; modo red dedicado = roadmap |

### Rendimiento / ops

| Queja real | Ángulo de marketing | Estado en Ordena |
|---|---|---|
| Carpetas grandes tardan / UI se traba | “Lista y mide pesos en segundo plano.” | FolderSizer async; mejoras FSEvents |
| Sin progreso claro al copiar/comprimir | “Progreso real y cancelable.” | Zip básico hoy; progreso = roadmap |
| Sin bandeja temporal al arrastrar | “Bandeja + Dropover: aparcas y sueltas cuando quieras.” | Bandeja + integración Dropover **ya** |

---

## 2. Dónde falla la competencia (oportunidad)

Usar con tono factual, sin difamar:

- **QSpace Pro / Bloom** — muy completos, pero quejas de **>1 GB RAM**, CPU en reposo, licencias online / límites de Macs. Bloom: reportes de pérdida al mover.
- **ForkLift 4** — fuerte en remoto; se siente más cliente FTP que reemplazo del Finder; merge al arrastrar flojo.
- **Path Finder** — veloz en red; rechazo al pasar a **suscripción anual**.
- **Cosmil / Fileside / Shuffle / Spacedrive** — ideas modernas; muchos aún incompletos o Electron/Alpha.
- **Nimble Commander / Marta** — ligeros pero UI muy técnica o bugs acumulados.
- **Yazi** — ultrarrápido, pero **solo Terminal**.

### Diferenciación Ordena (frase corta)

> Explorador nativo para Mac: rápido, privado, con bandeja y atajos que sí esperas — y IA/voz local opcionales, apagadas por defecto. Sin suscripción obligatoria para lo básico.

Pilares a repetir:

1. **Nativo Swift** (no Electron) — sin “impuesto de RAM” de stacks web.
2. **Ergonomía** — cortar/pegar, bandeja, ⌘+clic listo para mover, ⇧+flechas.
3. **Búsqueda en dos capas** — ⌘4 por nombre (ya); asistente/IA local por contenido y frases (roadmap).
4. **Smart Merge** — cero pérdida silenciosa (mensaje cuando esté la fase).
5. **IA y voz 100 % locales y opcionales** — no requisito; offline tras instalar modelos.
6. **Pago único / offline** (cuando exista licencia) — sin telemetría.

---

## 3. Headlines / bullets para landing

### Hero (ES)

- **Ordena.** El Finder que te hubiera gustado tener.
- Corta con ⌘X. Pega la ruta. Mueve con bandeja. Sin pelearte con Spotlight.
- Hecho en Swift para Apple Silicon. Privado. Sin chat molestando arriba de tus archivos.

### Bullets “Ya lo arreglamos” (solo lo que es verdad hoy)

- Cortar / copiar / pegar archivos (bandeja) con ⌘X · ⌘C · ⌘V  
- ⌘+clic: modo naranja “listo para mover” (sticky)  
- Selección múltiple con ⇧+clic y ⇧+flechas  
- Favoritos, historial atrás/adelante, 4 vistas (lista, iconos, columnas, galería)  
- Quick Look, Abrir con…, comprimir zip, deshacer movimientos (⌘Z)  
- Preferencias de orden propias (no vives del .DS_Store)  
- Actualizaciones desde ordena.iareal.net  

### Bullets “En camino” (no vender como hecho)

- Barra de ruta editable + Ir a carpeta  
- Búsqueda recursiva sin Spotlight  
- Smart Merge con vista previa  
- Asistente por lenguaje natural / voz local (opt-in)  

### Anti-claims (no usar)

- “El primer explorador con IA”  
- “Más rápido que Finder” sin benchmark  
- “Cero bugs en red/SMB”  
- “Reemplazo total del Finder / Dock stacks” (límites de Apple)

---

## 4. Testimonios-plantilla (para cuando haya usuarios)

Formato sugerido en la web:

> “En Finder no podía cortar archivos. En Ordena ⌘X y listo.”  
> — [nombre], [rol]

Guardar reseñas reales aquí cuando lleguen: `docs/testimonios/` (crear al primer cliente).

---

## 5. Enlaces producto

- Descarga / feed: `https://ordena.iareal.net/`  
- Repo app: privado; marketing en `web/` del monorepo Ordena  
- Catálogo de estilos landing: `tools/web-style-catalog/` · app_id `ordena`

---

## 6. Checklist pre-publish de un claim

Antes de poner un bullet en la landing:

1. ¿Está en la build publicada en `latest.json`?  
2. ¿Se puede demostrar en un vídeo de 15 s?  
3. ¿El copy dice “opcional” si es IA/voz?  
4. ¿No contradice Gatekeeper / notarización pendiente?
