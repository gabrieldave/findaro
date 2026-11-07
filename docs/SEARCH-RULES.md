# Ordena — reglas de búsqueda (producto)

Dos modos. No mezclar en el copy ni en la UX.

## 1. Búsqueda del explorador (⌘4 / Subcarpetas) — ya

| Regla | Valor |
|---|---|
| Dónde | Carpeta actual y **abajo**. Nunca arriba. |
| Qué | Solo **nombre** de archivo (extensión incluida). |
| Cómo | Coincidencia **parcial**, sin mayúsculas. |
| No | Contenido del archivo · comodines `*` `?` · Spotlight |

Ejemplo: `vibe` encuentra `vibesystems-ecosistema.zip`.

## 2. Búsqueda del asistente / IA local — roadmap

| Regla | Valor |
|---|---|
| Dónde | Misma carpeta actual y abajo (salvo que el usuario diga otra). |
| Qué | **Nombre + contenido** de archivos de texto legibles (txt, md, csv, json, código…). |
| Cómo | Frases naturales: «facturas de marzo», «que diga IBAN», «contratos firmados». |
| Motor | Reglas + Ollama opcional en el Mac. Sin nube. |
| Tool | `searchContent` (distinto de `searchFiles`). |

⌘4 sigue siendo el camino rápido por nombre. La IA no reemplaza ⌘4; lo complementa.
