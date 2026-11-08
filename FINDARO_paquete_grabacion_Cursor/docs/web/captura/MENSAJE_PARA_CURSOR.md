# Mensaje para pegar en Cursor

---

Soy el Director General de BLACK EYE. Te asigno la grabación del material de marketing de FINDARO.

**Antes de empezar:** lee en `main` de https://github.com/gabrieldave/black-eye-ai-operating-system los archivos `AI_START_HERE.md`, `VERSION`, `roles/CURSOR.md`, `protocols/APPROVALS.md` y `protocols/HANDOFF.md`.

**Tarea:** sigue al pie de la letra `docs/web/captura/GUION_CAPTURA.md` del repo `gabrieldave/orden` (rama `propuesta/landing-findaro-claude` o el parche que te paso). Usa:
- `scripts/demo/make_demo_dataset.py` para crear el set de prueba ficticio (y `--reset` entre tomas);
- `scripts/demo/capture.sh` para colocar la ventana, sacar las fotos, grabar los videos y empaquetar.

`capture.sh` lo escribió Claude sin acceso a un Mac: **pruébalo primero** con `prep`, `window` y `shot prueba`. Si algo falla, corrígelo y explica qué cambiaste en el handoff.

**Puntos clave:**
1. Graba desde una cuenta de macOS nueva llamada `demo`, sin Google Drive ni servicios conectados.
2. Mi pantalla es 21:9. No maximices Findaro: ventana de 1280×800 puntos centrada (`capture.sh window`).
3. Los videos V1-V8 son lo más importante; después las fotos P01-P15.
4. Revisa cada archivo al 100 % por privacidad antes de entregarlo.
5. Si los paneles no cambian a claro con la apariencia clara, no grabes el modo claro y repórtalo como defecto.

**Permisos:** ejecución local y lectura del repo. No modifiques `Sources/` ni `Tests/`, no hagas commit de capturas ni videos, no hagas push, no publiques y no subas nada a internet.

**Entrega:** el ZIP de `capture.sh pack` con `png/`, `video/`, `manifest.tsv` y un `HANDOFF.md` en formato BLACK EYE. Me lo pasas a mí.
