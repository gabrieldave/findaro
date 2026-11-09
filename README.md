# Findaro — explorador de archivos para Mac

**Findaro** es un explorador avanzado para macOS: doble panel, bandeja, Smart Merge con verificación SHA-256, FSEvents y asistente local opcional (Ollama).

**Versión:** `0.1.111` · **Bundle ID:** `app.findaro.files` · **Apple Silicon** · **macOS 15+**

## Instalar (beta privada)

```bash
./scripts/package-beta.sh
```

Genera `dist/beta/Findaro-0.1.111-arm64-beta.dmg` + SHA-256 + instrucciones.  
No publica al servidor ni sustituye tu instalación local.

Instrucciones para testers: `docs/BETA_PRIVADA.md`.

## Canal público (solo con autorización)

- Sitio: https://ordena.iareal.net/
- Feed: https://ordena.iareal.net/downloads/latest.json

`scripts/publish-update.sh` exige **Developer ID Application** y notarización. Sin certificado válido **aborta** (no publica ad hoc).

## Desarrollo

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift build -c release --product Orden
FINDARO_SKIP_INSTALL=1 ./scripts/package-app.sh
```

El producto SPM se llama `Orden` internamente; el bundle comercial es `Findaro`.

## Funciones

- Lista / iconos, doble panel, pestañas, FSEvents
- Nueva ventana (`⌘⌥N`), Terminal en carpeta (`⌘⌥T`)
- Omnibox (`⌘L`), Explorer keys, ocultos, vista plana
- Smart Merge SHA-256 + rollback
- Bandeja y TransferQueue con manifiesto de integridad
- Actualizador por canal (Findaro ≠ Ordena)
- Sin SFTP/S3/Drive/Dropbox (fuera de alcance por ahora)

## Icono

Arte aprobado: `Resources/AppIcon.icns`. No inventar marcas en código; `FindaroMark` carga ese asset.

## Contacto

- Soporte: [soporte@findaro.iareal.net](mailto:soporte@findaro.iareal.net) / [support@findaro.iareal.net](mailto:support@findaro.iareal.net)
- WhatsApp: [+52 56 4567 4407](https://wa.me/525645674407)
