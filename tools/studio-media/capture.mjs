#!/usr/bin/env node
/**
 * FINDARO studio-media generator
 * Playwright Chromium deviceScaleFactor:2 → Retina stills + Screen Studio videos
 * PROHIBIDO: screencapture 1x, tiras recortadas, tocar licencias/pagos/DB/DMG.
 */
import { chromium } from "playwright";
import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "../..");
const WEB = path.join(ROOT, "web/public");
const OUT = path.join(__dirname, "out");
const SOCIAL = path.join(process.env.HOME, "Desktop/FINDARO_SOCIAL_PACK_ES_EN");
const TEMPLATE = path.join(__dirname, "template.html");

const VIEWPORT = { width: 1280, height: 800 };
const SCALE = 2;
const WEBP_Q = 92;
const VIDEO_CRF = "18";
const FPS = 60;
const VIDEO_W = 2560;
const VIDEO_H = 1600;

const STILLS = [
  { name: "hero-dual-pane.webp", scene: "hero", theme: "midnight" },
  { name: "assistant-settings-optional-ollama-active.webp", scene: "assistant", theme: "midnight" },
  { name: "asistente-microfono.webp", scene: "assistant", theme: "midnight" },
  { name: "smart-merge-dialog-0-new.webp", scene: "merge", theme: "midnight" },
  { name: "papelera-restaurar.webp", scene: "trash", theme: "midnight" },
];

const VIDEOS = [
  { id: "v1-ai-voice", scene: "v1", seconds: 8 },
  { id: "v2-dual-pane-cut", scene: "v2", seconds: 9 },
  { id: "v3-smart-merge", scene: "v3", seconds: 9 },
  { id: "v4-deep-search", scene: "v4", seconds: 8 },
  { id: "v5-views-trash", scene: "v5", seconds: 8 },
  { id: "v6-themes", scene: "v6", seconds: 7 },
];

function run(cmd, args) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] });
    let err = "";
    p.stderr.on("data", (d) => (err += d.toString()));
    p.on("close", (code) => (code === 0 ? resolve() : reject(new Error(`${cmd} failed\n${err.slice(-2000)}`))));
  });
}

async function ensureDirs() {
  for (const lang of ["es", "en"]) {
    await fs.mkdir(path.join(WEB, "screenshots", lang), { recursive: true });
    await fs.mkdir(path.join(WEB, "videos", lang), { recursive: true });
    await fs.mkdir(path.join(OUT, lang, "raw"), { recursive: true });
    await fs.mkdir(path.join(SOCIAL, lang, "16x9"), { recursive: true });
    await fs.mkdir(path.join(SOCIAL, lang, "4x5"), { recursive: true });
  }
}

async function loadLocale(lang) {
  return JSON.parse(await fs.readFile(path.join(__dirname, "locales", `${lang}.json`), "utf8"));
}

async function bootPage(page, lang) {
  await page.goto(`file://${TEMPLATE}`);
  const i18n = await loadLocale(lang);
  await page.evaluate((data) => {
    window.FindaroStudio.applyI18n(data);
    window.FindaroStudio.setTheme("midnight");
  }, i18n);
  await page.waitForFunction(() => window.FindaroStudio?.ready === true);
  return i18n;
}

async function captureStill(page, lang, still) {
  await page.evaluate(async ({ scene, theme }) => {
    window.FindaroStudio.setTheme(theme);
    await window.FindaroStudio.scenes[scene]();
  }, still);
  await page.waitForTimeout(400);
  const buf = await page.screenshot({ type: "png" });
  // deviceScaleFactor:2 → 2560×1600
  const meta = await sharp(buf).metadata();
  if ((meta.width || 0) < 2000) {
    throw new Error(`Still not Retina: ${still.name} is ${meta.width}×${meta.height}`);
  }
  const out = path.join(WEB, "screenshots", lang, still.name);
  await sharp(buf).webp({ quality: WEBP_Q, effort: 5 }).toFile(out);
  console.log(`  still ${lang}/${still.name} (${meta.width}×${meta.height})`);
}

async function captureOg(browser, lang, i18n) {
  const context = await browser.newContext({
    viewport: { width: 1200, height: 630 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  await bootPage(page, lang);
  await page.evaluate((headline) => {
    window.FindaroStudio.showMode("og");
    document.getElementById("ogHeadline").textContent = headline;
  }, i18n.ogHeadline);
  await page.waitForTimeout(300);
  const buf = await page.screenshot({ type: "png" }); // 2400×1260
  const png = await sharp(buf).resize(1200, 630, { kernel: "lanczos3" }).png().toBuffer();
  await fs.writeFile(path.join(WEB, `og-${lang}.png`), png);
  if (lang === "es") await fs.writeFile(path.join(WEB, "og.png"), png);
  await sharp(buf).webp({ quality: WEBP_Q }).toFile(path.join(OUT, `og-${lang}@2x.webp`));
  await context.close();
  console.log(`  og-${lang}.png`);
}

async function captureVideo(browser, lang, clip) {
  const rawDir = path.join(OUT, lang, "raw");
  await fs.mkdir(rawDir, { recursive: true });

  // Native 2560×1600 capture: CSS stage scaled 2× inside viewport (vector UI stays sharp).
  const context = await browser.newContext({
    viewport: { width: VIDEO_W, height: VIDEO_H },
    deviceScaleFactor: 1,
    recordVideo: { dir: rawDir, size: { width: VIDEO_W, height: VIDEO_H } },
  });
  const page = await context.newPage();
  await page.goto(`file://${TEMPLATE}`);
  await page.addStyleTag({
    content: `
      html, body { width: ${VIDEO_W}px !important; height: ${VIDEO_H}px !important; overflow: hidden; }
      #ogRoot { display: none !important; }
      .stage {
        width: 1280px !important; height: 800px !important;
        transform: scale(2); transform-origin: 0 0;
      }
    `,
  });
  const i18n = await loadLocale(lang);
  await page.evaluate((data) => {
    window.FindaroStudio.applyI18n(data);
    window.FindaroStudio.setTheme("midnight");
  }, i18n);
  await page.waitForTimeout(250);

  const need = clip.seconds * 1000;
  const t0 = Date.now();
  await page.evaluate(async ({ scene, ms }) => {
    await window.FindaroStudio.scenes[scene](ms);
  }, { scene: clip.scene, ms: need });
  const left = need - (Date.now() - t0);
  if (left > 0) await page.waitForTimeout(left);

  const posterBuf = await page.screenshot({ type: "png" });
  await sharp(posterBuf)
    .resize(VIDEO_W, VIDEO_H, { fit: "cover" })
    .webp({ quality: WEBP_Q })
    .toFile(path.join(WEB, "videos", lang, `${clip.id}-poster.webp`));
  await sharp(posterBuf)
    .resize(1280, 800, { fit: "cover" })
    .jpeg({ quality: 92 })
    .toFile(path.join(WEB, "videos", lang, `${clip.id}-poster.jpg`));

  const video = page.video();
  await page.close();
  const rawPath = await video.path();
  await context.close();

  const mp4Out = path.join(WEB, "videos", lang, `${clip.id}.mp4`);
  await run("ffmpeg", [
    "-y", "-i", rawPath,
    "-vf", `fps=${FPS},scale=${VIDEO_W}:${VIDEO_H}:flags=lanczos`,
    "-c:v", "libx264", "-pix_fmt", "yuv420p",
    "-crf", VIDEO_CRF, "-preset", "slow",
    "-movflags", "+faststart", "-an",
    "-t", String(clip.seconds),
    mp4Out,
  ]);

  // Social 16:9
  await run("ffmpeg", [
    "-y", "-i", mp4Out,
    "-vf", "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=#060B16,fps=60",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", VIDEO_CRF, "-preset", "slow",
    "-movflags", "+faststart", "-an",
    path.join(SOCIAL, lang, "16x9", `${clip.id}.mp4`),
  ]);

  // Social 4:5 with commercial title (PNG overlay — ffmpeg sin libfreetype/drawtext)
  const overlayPath = path.join(OUT, lang, `title-4x5.png`);
  const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="220">
  <rect width="1080" height="220" fill="#060B16"/>
  <text x="540" y="90" text-anchor="middle" font-family="Helvetica Neue, Arial, sans-serif" font-size="34" font-weight="700" fill="#ffffff">${escapeXml(i18n.socialTitle)}</text>
  <text x="540" y="140" text-anchor="middle" font-family="Helvetica Neue, Arial, sans-serif" font-size="22" fill="#94A3B8">${escapeXml(i18n.socialSub)}</text>
</svg>`;
  await sharp(Buffer.from(svg)).png().toFile(overlayPath);
  const tmp45 = path.join(OUT, lang, `${clip.id}-45-base.mp4`);
  await run("ffmpeg", [
    "-y", "-i", mp4Out,
    "-vf", "scale=1080:980:force_original_aspect_ratio=decrease,pad=1080:1350:(ow-iw)/2:(oh-ih)/2+90:color=#060B16,fps=60",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", VIDEO_CRF, "-preset", "slow",
    "-movflags", "+faststart", "-an",
    tmp45,
  ]);
  await run("ffmpeg", [
    "-y", "-i", tmp45, "-i", overlayPath,
    "-filter_complex", "overlay=0:0",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", VIDEO_CRF, "-preset", "slow",
    "-movflags", "+faststart", "-an",
    path.join(SOCIAL, lang, "4x5", `${clip.id}.mp4`),
  ]);

  console.log(`  video ${lang}/${clip.id}.mp4`);
}

function escapeXml(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

async function replaceLegacyStrips(lang) {
  const hero = path.join(WEB, "screenshots", lang, "hero-dual-pane.webp");
  for (const legacy of [
    "dual-pane-headers-origin-and.webp",
    "two-photos-selected-in-the.webp",
    "the-same-two-photos-dimmed.webp",
    "clipboard-tray-with-multiple-files.webp",
    "findaro-filter-bar-with-buttons.webp",
  ]) {
    await fs.copyFile(hero, path.join(WEB, "screenshots", lang, legacy));
  }
}

async function main() {
  const args = new Set(process.argv.slice(2));
  const onlyLang = [...args].find(a => a.startsWith('--lang='))?.split('=')[1];
  const skipStills = args.has('--skip-stills');
  const langs = onlyLang ? [onlyLang] : ['es', 'en'];

  console.log("==> FINDARO studio-media Retina @2x / 60fps / crf 18");
  await ensureDirs();
  const browser = await chromium.launch({
    headless: true,
    args: ["--force-color-profile=srgb", "--font-render-hinting=none"],
  });

  try {
    for (const lang of langs) {
      console.log(`\n== ${lang}`);
      let i18n = await loadLocale(lang);
      if (!skipStills) {
        const context = await browser.newContext({
          viewport: VIEWPORT,
          deviceScaleFactor: SCALE,
        });
        const page = await context.newPage();
        i18n = await bootPage(page, lang);
        for (const still of STILLS) await captureStill(page, lang, still);
        await context.close();
        await captureOg(browser, lang, i18n);
      }
      for (const clip of VIDEOS) await captureVideo(browser, lang, clip);
      await replaceLegacyStrips(lang);
    }
  } finally {
    await browser.close();
  }
  console.log("\nOK");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
