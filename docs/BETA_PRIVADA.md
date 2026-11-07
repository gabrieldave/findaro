# Findaro 0.1.80 — beta privada

## Identidad

| Campo | Valor |
|---|---|
| Producto | Findaro |
| Versión | 0.1.80 |
| Build | 86 |
| Bundle ID | `app.findaro.files` |
| macOS | 15+ |
| Arch | Apple Silicon arm64 |

## Generar instalador (sin tocar producción)

```bash
./scripts/package-beta.sh
```

Salida:

- `dist/beta/Findaro-0.1.80-arm64-beta.dmg`
- `dist/beta/Findaro-0.1.80-arm64-beta.dmg.sha256`
- `dist/beta/INSTRUCCIONES-BETA.txt`
- Copias en el Escritorio

No ejecuta `publish-update.sh`, no modifica el feed, no instala en `/Applications`.

## Firma y notarización

- **Developer ID Application**: requerido para distribución comercial / Gatekeeper limpio.
- En este entorno de desarrollo suele existir solo **Apple Development** → la beta se firma **ad hoc**.
- **Notarización: NO** en builds ad hoc. No afirmar lo contrario.
- Testers: clic derecho → Abrir la primera vez.

Para publicar al canal oficial más adelante: certificado Developer ID + `scripts/publish-update.sh` (aborta sin Dev ID).

## Canales de actualización

El feed `latest.json` tiene dos canales exclusivos:

- `app.findaro.files` → `findaro_dmg_url` + `findaro_sha256`
- `app.ordena.files` → `dmg_url` + `sha256`

Findaro nunca instala el paquete Ordena y viceversa.

## Icono

El arte aprobado vive en `Resources/AppIcon.icns`. No regenerar en CI ni en empaquetado beta.
