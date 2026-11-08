# Checklist — Evidencia visual auténtica, calidad y privacidad

## Precondiciones

- [ ] Reglas de BLACK EYE actualizadas, versión documentada.
- [ ] FINDARO real abierto en Mac autorizado, bundle id y build anotados.
- [ ] Datos ficticios en un directorio temporal propio de la demostración.
- [ ] Ventana identificada con `capture-window.sh list`.
- [ ] Nada que vaya a enviarse fuera del equipo sin autorización.

## Cada captura

- [ ] Es un PNG sin reconstrucción ni manipulación de la UI.
- [ ] La escena corresponde a una función comprobada de la versión ejecutada.
- [ ] Se lee el contenido principal sin ampliar artificialmente el PNG.
- [ ] No aparecen rutas de usuario, correo, nombre completo, cuentas, medios personales, tokens, etc.
- [ ] No se ve un diálogo de error, notificación, Dock, Terminal, editor ni ventana ajena.
- [ ] La luz y sombra provienen de la interfaz auténtica; no cambiar el tema en posproducción.
- [ ] El estado es coherente: selección/foco/transferencia/diálogo en el punto correcto.
- [ ] Se guardaron tamaño, timestamp y SHA-256 en `manifest.tsv`.
- [ ] Se abrió manualmente el PNG final para inspección.
- [ ] Marcado REVISADA por Director General antes de integrar en web.

## Prueba de nitidez

Ideal: capturar a resolución Retina nativa con ventana amplia. Para portada,
recomendar ancho en píxeles ≥ 1600 si el equipo lo permite. Si no, documentar
ancho real y evitar escalar la captura por encima de su tamaño nativo.
No inventar más resolución mediante generadores o escaladores.

## Seguridad

La carpeta `~/Downloads/FINDARO_CAPTURE_REVIEW` NO es pública por sí misma.
No colocar capturas con nombres/rutas privadas en `web/public` ni en commits.
No borrar carpetas ni documentos ajenos a las fixtures. No limpiar la carpeta
`$TMPDIR` por fuerza sin autorización. El dataset temporal se elimina manualmente
cuando se verifique que no se necesita, limitado a su propia ruta.

## Estado

CAPTURADA: existe PNG original y manifest.
REVISADA: inspección manual y autorización para integrarla.
BLOQUEADA: permisos/compilación/función impiden capturar.
NO VERIFICADA: todavía no se ha demostrado en ejecución.
NO IMPLEMENTADA: ausencia documentada para esa versión.
