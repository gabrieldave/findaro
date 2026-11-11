---
name: findaro-release
description: >-
  Checklist obligatorio de release FINDARO: codesign, notarize, licencias Ed25519,
  feed latest.json, keychain Data Protection (sin spam ACL), puente Ordena, Cloudflare purge.
  Usar al publicar update, bump, DMG, notarizar o si el usuario dice “FINDARO release”.
---

# FINDARO Release

Leer y cumplir `.cursor/rules/findaro-release-checklist.mdc` completo antes de publicar.

## Qué NO hacer

- Regenerar `LICENSE_SIGNING_*` / públicas embebidas “por si acaso”
- Regenerar clave del feed Ed25519
- Publicar con firma adhoc
- Declarar auditado sin tabla OK/FAIL
- Omitir keychain/ACL (causa miles de «Permitir» tras update)
- Omitir purge de Cloudflare

## Prompt del usuario

```
FINDARO release — checklist completo
No saltes licencias, feed, keychain/ACL, notary ni purge.
Tabla OK/FAIL al final. Sin regenerar claves.
```
