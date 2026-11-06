---
name: web-style-catalog
description: >-
  Entiende la app VibeSystems (app_profile + app_id), recomienda estilos MotionSites
  GRATIS por bloque (hero, pricing, 3D…) y luego implementa. Usar SIEMPRE al pedir
  qué landing usar, estilo web, rediseño marketing, hero 3D, o al trabajar landing.css
  page.tsx. Ejecutar recommend.py antes de proponer diseño.
---

# Web Style Catalog — VibeSystems

## Paso 0 — Entender la app (OBLIGATORIO)

1. Lee `.cursor/app.json` del repo → obtén `app_id` (ej. `cursia`)
2. Si no existe, infiere del `package.json`, README o pregunt al usuario
3. Lee `tools/web-style-catalog/apps.registry.json` → `apps[app_id].app_profile`
   - `product`, `audience`, `tone`, `differentiator`
   - `style_rationale` — por qué cada bloque usa un prompt concreto
4. Ejecuta en terminal:
   ```bash
   python3 tools/web-style-catalog/recommend.py APP_ID
   ```
   (En Cursia: `python3 tools/web-style-catalog/recommend.py cursia`)

## Paso 1 — Recomendar (antes de codear)

Presenta al usuario una **tabla por bloque**:

| Bloque | Recomendado | Alternativa | Por qué |
|--------|-------------|-------------|---------|
| hero | 3D Portfolio ⭐ | DesignPro Academy | Cards 3D = slides del producto |

- ⭐ = `curated_picks` del app_id
- Score desde `catalog.json` → `app_scores[app_id]`
- URL: `page_url` en MotionSites → botón **Copy**
- **No implementes** hasta que el usuario confirme o diga "aplica"

## Paso 2 — Consultar catálogo

Archivos (repo o global `~/.cursor/skills/web-style-catalog/`):

| Archivo | Uso |
|---------|-----|
| `apps.registry.json` | Perfil, theme, picks |
| `catalog.json` | 200 items + scores |
| `recommend.py` | Tabla automática |

Filtro manual:
```javascript
items.filter(i => i.block === "hero" && i.app_scores.cursia >= 50)
      .sort((a,b) => b.app_scores.cursia - a.app_scores.cursia)
```

## Paso 3 — Implementar

- Theme del registry > colores del prompt MotionSites
- Un estilo coherente por bloque (stack ya curado en `applied_styles` si existe)
- **3D obligatorio en toda app web:** seleccionar al menos un patrón/asset 3D significativo para hero, producto o experiencia principal. No usar 3D decorativo sin relación con el producto.
- El 3D debe tener fallback estático, respetar `prefers-reduced-motion`, ser responsive y no bloquear LCP/INP.
- Landing Cursia: `src/app/landing.css`, `src/app/page.tsx`

## Cursia — resumen rápido

| Bloque | TOP MotionSites gratis | Razón |
|--------|------------------------|-------|
| hero | **3D Portfolio** | Cards 3D con producto (slides) |
| features | Glow Features | Glow naranja/violeta |
| pricing | Rocket Pricing | 3 tiers, central destacado |
| testimonials | Radial Diagram | Stats + quotes |
| faq | FAQ CTA | Accordion + cierre |
| cta | Liquid Glass CTA | Glass dark editorial |
| background | Blue Purple Glow, Ember Glow | Theme colors |

Perfil completo: `apps.cursia.app_profile` en registry.

## Registrar app nueva

Copia `_template` en `apps.registry.json` → completa `app_profile` → regenera catálogo.

## Reglas

1. **Recomendar primero**, codear después
2. Solo prompts **Copy** (gratis) salvo que el usuario pague Premium
3. Evitar tags en `avoid` del app_id
4. Documentar prompts usados al implementar
5. Confirmar que existe una capa visual 3D significativa en desktop y móvil; si el catálogo no ofrece una adecuada, diseñarla de forma compatible con el theme

Tras landing bilingüe: aplicar también i18n es/en (`plantillas/I18N.md`, skill `vibesystems-i18n`, §12.10).

Guía: `reference.md`
