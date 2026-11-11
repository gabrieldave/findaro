# FINDARO studio-media

Generador visual Retina (Playwright / Chromium `deviceScaleFactor: 2`) + ffmpeg (`-crf 18`, 60 fps).

**No usa** `screencapture`. No toca licencias, pagos, DB ni DMGs.

```bash
cd tools/studio-media
npm install
npx playwright install chromium
node capture.mjs
```

Salidas:
- `web/public/screenshots/{es,en}/*.webp` @2x (~2560×1600)
- `web/public/videos/{es,en}/v1…v6.mp4` + posters
- `web/public/og-{es,en}.png` / `og.png`
- `~/Desktop/FINDARO_SOCIAL_PACK_ES_EN/{es,en}/{16x9,4x5}/`
