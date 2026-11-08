# FINDARO — CAPTURE_PLAN

**Fecha UTC:** 2026-11-07  
**BLACK EYE:** 1.3.1 (consultado RAW/clone)  
**Repo:** gabrieldave/orden · rama `main` · commit `cbe52c6`  
**App instalada:** Findaro.app · `app.findaro.files` · **0.1.86** (build **92**)  
**Web actual:** `web/src/app/page.tsx` — hero + features (doble panel, Smart Merge, bandeja, búsqueda) + descarga  
**Publicación:** NO (orden del Director: no publicar)

## Inventario de secciones web ↔ evidencia

| Sección web | Beneficio prometido | Función / código | Escena | Estado plan |
|---|---|---|---|---|
| Hero | Explorador nativo bajo control | `ContentView` ventana principal | `portada-oscuro` | CAPTURAR P0 |
| Features · doble panel | Origen → Destino | `SecondaryBrowserPane`, dual pane | `doble-panel` | CAPTURAR P0 |
| Features · transferencias | Bandeja / cola | `DropShelfView`, shelf | `bandeja-preparada` | CAPTURAR P0 |
| Features · Smart Merge | SHA-256 / conflictos | `MergePreviewSheet`, `FolderMerge` | `smart-merge-conflictos` | CAPTURAR P1 |
| Features · búsqueda | Búsqueda recursiva | `RecursiveSearchPanel` | `busqueda-recursiva` | CAPTURAR P1 |
| Apariencia | Claro/oscuro | Appearance | `modo-claro` | CAPTURAR P1 |
| Asistente local | Reglas + Ollama opcional | `AssistantPanel` | `asistente-local` | P2 — solo si IA off / NO VERIFICADA si no se prueba |
| Vistas | Iconos / columnas / galería | `BrowserLayoutViews` | vistas P2 | Opcional tras P0/P1 |

## Prioridad de esta corrida

1. Fixtures temporales (sin datos personales)  
2. Abrir Findaro 0.1.86 y navegar a ORIGEN/DESTINO demo  
3. Capturar P0 + P1 mínimas con `capture-window.sh`  
4. Revisar PNG (privacidad) → handoff  
5. **No** copiar a `web/public`, **no** commit de assets, **no** deploy  

## Resultado de la corrida (2026-11-07)

| Escena | Estado | Notas |
|---|---|---|
| portada-oscuro | CAPTURADA | En dual pane (no un panel limpio) |
| doble-panel | CAPTURADA | ORIGEN+DESTINO demo |
| bandeja-preparada | CAPTURADA | 2 ítems en bandeja |
| smart-merge-conflictos | CAPTURADA | Sheet real; cancelado sin merge |
| busqueda-recursiva | CAPTURADA | Filtro «plan»; lista visual confusa |
| modo-claro | CAPTURADA | Verificar tema real de la app |
| P2 vistas / asistente | NO CAPTURADA | Fuera del mínimo |

**Entrega:** `~/Downloads/FINDARO_CAPTURE_REVIEW/` + `HANDOFF_CHATGPТ.md`  
**No** copiado a `web/public`. **No** commit de PNG.  
**Privacidad:** correos en Ubicaciones → **no apto web** sin DG.

## Notas

- Capturas históricas en `docs/creative/.../capturas/` = entrega ~0.1.75; **no** presentarlas como 0.1.86.  
- Fixtures TMPDIR bloqueadas por AgentPolicy; usar `~/Documents/FINDARO-Demo-Captura`.  
