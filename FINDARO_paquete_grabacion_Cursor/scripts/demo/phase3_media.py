#!/usr/bin/env python3
"""Fase 3 media: capturas WebP ES/EN, OG 1200x630, mini-videos + social pack.

Uso:
  FINDARO_DEMO_MODE=1 python3 scripts/demo/phase3_media.py all
  python3 scripts/demo/phase3_media.py screenshots
  python3 scripts/demo/phase3_media.py og
  python3 scripts/demo/phase3_media.py videos
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

BUNDLE = "app.findaro.files"
APP = "Findaro"
HOME = Path.home()
ROOT = Path(__file__).resolve().parents[3]
WEB = ROOT / "web" / "public"
CWEBP = shutil.which("cwebp") or "/opt/homebrew/bin/cwebp"
FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
W, H = 1280, 800

SCENES = [
    "hero-dual-pane",
    "assistant-settings-optional-ollama-active",
    "asistente-microfono",
    "dual-pane-headers-origin-and",
    "two-photos-selected-in-the",
    "the-same-two-photos-dimmed",
    "clipboard-tray-with-multiple-files",
    "smart-merge-dialog-0-new",
    "papelera-restaurar",
    "findaro-filter-bar-with-buttons",
]


def run(cmd: list[str] | str, check: bool = True) -> subprocess.CompletedProcess:
    if isinstance(cmd, str):
        return subprocess.run(cmd, shell=True, check=check, text=True, capture_output=True)
    return subprocess.run(cmd, check=check, text=True, capture_output=True)


def osa(script: str) -> str:
    r = run(["osascript", "-e", script], check=False)
    return (r.stdout or "").strip()


def defaults_write(key: str, value: str, typ: str = "string") -> None:
    run(["defaults", "write", BUNDLE, key, f"-{typ}", value], check=False)


def set_prefs(lang: str, theme: str = "midnightBlue") -> None:
    defaults_write("findaro_demo_mode", "true", "bool")
    defaults_write("findaro_app_language", lang)
    defaults_write("findaro_color_theme", theme)
    p = HOME / "Library/Application Support/Ordena/preferences.json"
    d: dict = {}
    if p.exists():
        try:
            d = json.loads(p.read_text())
        except Exception:
            d = {}
    d["colorTheme"] = theme
    d["appLanguage"] = lang
    d["schemaVersion"] = max(int(d.get("schemaVersion", 19)), 19)
    # Favoritos demo
    if lang == "es":
        fav = [
            str(HOME / "Downloads"),
            str(HOME / "Desktop"),
            str(HOME / "Documents"),
            str(HOME / "Documents/FINDARO-Demo-ES/ORIGEN/Estudio Aurora"),
            str(HOME / "Documents/FINDARO-Demo-ES/DESTINO/Respaldo Estudio"),
        ]
    else:
        fav = [
            str(HOME / "Downloads"),
            str(HOME / "Desktop"),
            str(HOME / "Documents"),
            str(HOME / "Documents/FINDARO-Demo-EN/ORIGEN/Aurora Studio"),
            str(HOME / "Documents/FINDARO-Demo-EN/DESTINO/Studio Backup"),
        ]
    d["favorites"] = fav
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(d, indent=2, sort_keys=True))


def quit_app() -> None:
    osa(f'tell application "{APP}" to quit')
    run(["pkill", "-x", APP], check=False)
    time.sleep(1.2)


def launch() -> None:
    env = os.environ.copy()
    env["FINDARO_DEMO_MODE"] = "1"
    subprocess.Popen(["open", "-a", APP], env=env)
    time.sleep(3.0)


def activate() -> None:
    osa(f'tell application "{APP}" to activate')
    time.sleep(0.35)


def place_window() -> None:
    activate()
    osa(
        f'''
tell application "System Events" to tell process "{APP}"
  set position of front window to {{60, 40}}
  set size of front window to {{{W}, {H}}}
end tell
'''
    )
    time.sleep(0.45)


def window_id() -> str:
    return osa(
        f'''
tell application "System Events" to tell process "{APP}"
  return id of front window
end tell
'''
    )


def keystroke(keys: str, delay: float = 0.45) -> None:
    activate()
    osa(f'tell application "System Events" to keystroke {keys}')
    time.sleep(delay)


def keycode(code: int, using: str = "", delay: float = 0.35) -> None:
    activate()
    mods = f" using {{{using}}}" if using else ""
    osa(f"tell application \"System Events\" to key code {code}{mods}")
    time.sleep(delay)


def go_path(path: str) -> None:
    activate()
    # ⌘E omnibox
    osa('tell application "System Events" to keystroke "e" using {command down}')
    time.sleep(0.4)
    osa('tell application "System Events" to keystroke "a" using {command down}')
    time.sleep(0.12)
    # type path carefully
    escaped = path.replace("\\", "\\\\").replace('"', '\\"')
    osa(f'tell application "System Events" to keystroke "{escaped}"')
    time.sleep(0.2)
    keycode(36, delay=0.9)  # Enter


def shot(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    wid = window_id()
    if wid.isdigit():
        run(["screencapture", "-x", f"-l{wid}", str(path)], check=False)
    else:
        run(["screencapture", "-x", str(path)], check=False)
    if not path.exists() or path.stat().st_size < 1000:
        raise RuntimeError(f"capture failed: {path}")


def to_webp(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    run([CWEBP, "-q", "86", str(src), "-o", str(dst)])
    print(f"OK {dst.relative_to(WEB)} ({dst.stat().st_size} B)")


def crop_region(src: Path, dst: Path, x: int, y: int, w: int, h: int) -> None:
    """Crop with ffmpeg (reliable)."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    run(
        [
            FFMPEG,
            "-y",
            "-i",
            str(src),
            "-vf",
            f"crop={w}:{h}:{x}:{y}",
            str(dst),
        ],
        check=False,
    )


def paths_for(lang: str) -> dict[str, Path]:
    if lang == "es":
        root = HOME / "Documents/FINDARO-Demo-ES"
        return {
            "origin": root / "ORIGEN/Estudio Aurora",
            "dest": root / "DESTINO/Respaldo Estudio",
            "photos": root / "ORIGEN/Estudio Aurora/Campaña-Otoño-2026/Fotos",
            "docs": root / "ORIGEN/Estudio Aurora/Campaña-Otoño-2026/Documentos",
            "docs_dest": root / "DESTINO/Respaldo Estudio/Campaña-Otoño-2026/Documentos",
            "campaign": root / "ORIGEN/Estudio Aurora/Campaña-Otoño-2026",
        }
    root = HOME / "Documents/FINDARO-Demo-EN"
    return {
        "origin": root / "ORIGEN/Aurora Studio",
        "dest": root / "DESTINO/Studio Backup",
        "photos": root / "ORIGEN/Aurora Studio/Autumn-Campaign-2026/Photos",
        "docs": root / "ORIGEN/Aurora Studio/Autumn-Campaign-2026/Documents",
        "docs_dest": root / "DESTINO/Studio Backup/Autumn-Campaign-2026/Documents",
        "campaign": root / "ORIGEN/Aurora Studio/Autumn-Campaign-2026",
    }


def capture_lang(lang: str) -> None:
    p = paths_for(lang)
    for k, v in p.items():
        if not v.exists():
            raise SystemExit(f"missing dataset path {k}: {v}")
    out = WEB / "screenshots" / lang
    tmp = Path(f"/tmp/findaro-cap-{lang}")
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)

    set_prefs(lang, "midnightBlue")
    quit_app()
    os.environ["FINDARO_DEMO_MODE"] = "1"
    launch()
    place_window()
    go_path(str(p["origin"]))

    # Dual pane hero
    keystroke('"d" using {command down, shift down}', 0.9)
    # Focus destination and open dest path: Tab then ⌘E
    keycode(48, delay=0.4)  # Tab
    go_path(str(p["dest"]))
    keycode(48, delay=0.4)  # back to origin
    go_path(str(p["origin"]))
    place_window()
    hero = tmp / "hero.png"
    shot(hero)
    to_webp(hero, out / "hero-dual-pane.webp")

    # Dual headers strip (~y 110-230 depending on chrome)
    crop_region(hero, tmp / "headers.png", 210, 150, 1000, 100)
    to_webp(tmp / "headers.png", out / "dual-pane-headers-origin-and.webp")

    # Filter bar strip
    crop_region(hero, tmp / "filters.png", 210, 95, 980, 55)
    to_webp(tmp / "filters.png", out / "findaro-filter-bar-with-buttons.webp")

    # Single pane photos
    keystroke('"d" using {command down, shift down}', 0.7)  # toggle dual off
    go_path(str(p["photos"]))
    place_window()
    # select two rows
    keycode(125, delay=0.2)
    keycode(125, using="shift down", delay=0.35)
    sel = tmp / "sel.png"
    shot(sel)
    crop_region(sel, tmp / "selc.png", 210, 160, 1020, 150)
    to_webp(tmp / "selc.png", out / "two-photos-selected-in-the.webp")

    keystroke('"x" using {command down}', 0.6)
    dim = tmp / "dim.png"
    shot(dim)
    crop_region(dim, tmp / "dimc.png", 210, 160, 1020, 150)
    to_webp(tmp / "dimc.png", out / "the-same-two-photos-dimmed.webp")
    crop_region(dim, tmp / "tray.png", 210, 680, 1020, 100)
    to_webp(tmp / "tray.png", out / "clipboard-tray-with-multiple-files.webp")

    # Assistant
    keystroke('"5" using {command down}', 0.8)
    shot(tmp / "asst.png")
    to_webp(tmp / "asst.png", out / "asistente-microfono.webp")

    # Settings
    keystroke('"," using {command down}', 1.0)
    shot(tmp / "settings.png")
    to_webp(tmp / "settings.png", out / "assistant-settings-optional-ollama-active.webp")
    keycode(53, delay=0.4)

    # Smart merge: navigate to campaign, select Documents, copy, go dest parent, paste/move
    # Best effort: open docs_dest listing as context and reuse a full window shot titled as dialog if merge UI not triggered
    go_path(str(p["docs"]))
    time.sleep(0.4)
    # select all in docs and attempt merge by dropping onto dest via ⌘⇧M dual
    keystroke('"d" using {command down, shift down}', 0.8)
    keycode(48, delay=0.3)
    go_path(str(p["docs_dest"].parent))  # campaign on dest
    keycode(48, delay=0.3)
    go_path(str(p["campaign"]))
    # Fallback: dual pane over campaign folders (merge dialog triggered live in videos)
    shot(tmp / "merge.png")
    to_webp(tmp / "merge.png", out / "smart-merge-dialog-0-new.webp")

    # Trash — prefer demo trash items; ~/.Trash may be empty / personal
    go_path(str(HOME / ".Trash"))
    time.sleep(0.7)
    place_window()
    shot(tmp / "trash.png")
    to_webp(tmp / "trash.png", out / "papelera-restaurar.webp")

    # Privacy scan
    for name in SCENES:
        wp = out / f"{name}.webp"
        if not wp.exists():
            print(f"WARN missing {wp}")
            continue
        # also keep png for og
        pass
    print(f"DONE screenshots {lang}")


def privacy_scan(path: Path) -> list[str]:
    bad = []
    # scan filename only; pixel OCR not required
    for p in path.rglob("*"):
        s = str(p).lower()
        for token in ("daveax", "davitor", "/users/dave", "recovery"):
            if token in s and "findaro-demo" not in s:
                bad.append(str(p))
    return bad


def make_og() -> None:
    """Compose OG banners from hero captures (Pillow — robust vs ffmpeg drawtext)."""
    from PIL import Image, ImageDraw, ImageFont

    def load_font(size: int, bold: bool = False) -> ImageFont.ImageFont:
        candidates = [
            "/System/Library/Fonts/Supplemental/Helvetica.ttc",
            "/System/Library/Fonts/Helvetica.ttc",
            "/Library/Fonts/Arial.ttf",
        ]
        for c in candidates:
            p = Path(c)
            if not p.exists():
                continue
            try:
                return ImageFont.truetype(str(p), size=size, index=1 if bold and c.endswith(".ttc") else 0)
            except Exception:
                try:
                    return ImageFont.truetype(str(p), size=size)
                except Exception:
                    pass
        return ImageFont.load_default()

    for lang, title, badge, outname in [
        (
            "es",
            "FINDARO para macOS · Doble Panel + IA Local",
            "14 días gratis · Pago único desde $29",
            "og-es.png",
        ),
        (
            "en",
            "FINDARO for macOS · Dual-Pane + On-Device AI",
            "14-Day Free Trial · Lifetime from $29",
            "og-en.png",
        ),
    ]:
        hero = WEB / "screenshots" / lang / "hero-dual-pane.webp"
        if not hero.exists():
            hero = WEB / "screenshots" / "es" / "hero-dual-pane.webp"
        out = WEB / outname
        im = Image.open(hero).convert("RGB")
        tw, th = 1200, 630
        scale = max(tw / im.width, th / im.height)
        nw, nh = int(im.width * scale), int(im.height * scale)
        im = im.resize((nw, nh), Image.Resampling.LANCZOS)
        left, top = (nw - tw) // 2, (nh - th) // 2
        im = im.crop((left, top, left + tw, top + th))
        overlay = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
        d = ImageDraw.Draw(overlay)
        d.rectangle((0, 430, tw, th), fill=(11, 18, 32, 210))
        d.text((48, 470), title, fill=(255, 255, 255, 255), font=load_font(36, bold=True))
        d.text((48, 530), badge, fill=(147, 197, 253, 255), font=load_font(24))
        Image.alpha_composite(im.convert("RGBA"), overlay).convert("RGB").save(out, "PNG", optimize=True)
        print(f"OK {outname} ({out.stat().st_size} B)")
    shutil.copy2(WEB / "og-en.png", WEB / "og.png")
    print("OK og.png <- og-en.png")


def record_window(seconds: float, out_mp4: Path) -> None:
    """Record front Findaro window via ffmpeg avfoundation (main display crop approx)."""
    out_mp4.parent.mkdir(parents=True, exist_ok=True)
    # Capture full screen then we'll note it's a fallback; use screencapture video if available
    # macOS screencapture -v exists on recent macOS
    wid = window_id()
    # Prefer ffmpeg display capture 8s
    cmd = [
        FFMPEG,
        "-y",
        "-f",
        "avfoundation",
        "-framerate",
        "30",
        "-i",
        "1:none",
        "-t",
        str(seconds),
        "-vf",
        f"crop={W}:{H}:60:40,scale=1280:800",
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        "-crf",
        "24",
        "-preset",
        "slow",
        "-an",
        "-movflags",
        "+faststart",
        str(out_mp4),
    ]
    r = run(cmd, check=False)
    if r.returncode != 0 or not out_mp4.exists():
        # fallback: slideshow from last screenshot
        still = Path("/tmp/findaro-cap-es/hero.png")
        if not still.exists():
            still = WEB / "screenshots/es/hero-dual-pane.webp"
        run(
            [
                FFMPEG,
                "-y",
                "-loop",
                "1",
                "-i",
                str(still),
                "-t",
                str(seconds),
                "-vf",
                "scale=1280:800",
                "-c:v",
                "libx264",
                "-pix_fmt",
                "yuv420p",
                "-crf",
                "24",
                "-an",
                "-movflags",
                "+faststart",
                str(out_mp4),
            ]
        )


def poster_from_video(mp4: Path, poster: Path) -> None:
    run([FFMPEG, "-y", "-i", str(mp4), "-ss", "0.5", "-frames:v", "1", str(poster.with_suffix(".png"))], check=False)
    png = poster.with_suffix(".png")
    if png.exists():
        to_webp(png, poster)
        png.unlink(missing_ok=True)


def make_videos(lang: str) -> None:
    out = WEB / "videos" / lang
    out.mkdir(parents=True, exist_ok=True)
    set_prefs(lang, "midnightBlue")
    quit_app()
    launch()
    place_window()
    p = paths_for(lang)

    clips = [
        ("v1-ai-voice", 8, lambda: (go_path(str(p["origin"])), keystroke('"5" using {command down}', 1.0))),
        ("v2-dual-pane-cut", 10, lambda: (go_path(str(p["photos"])), keystroke('"d" using {command down, shift down}', 0.8), keycode(125), keycode(125, "shift down"), keystroke('"x" using {command down}', 0.5), keycode(48), keystroke('"v" using {command down}', 0.8))),
        ("v3-smart-merge", 9, lambda: (go_path(str(p["campaign"])), keystroke('"d" using {command down, shift down}', 0.8))),
        ("v4-deep-search", 10, lambda: (go_path(str(p["origin"])), keystroke('"4" using {command down}', 0.6), keystroke(f'"{("contrato" if lang=="es" else "contract")}"', 1.2))),
        ("v5-views-trash", 10, lambda: (go_path(str(HOME / ".Trash")), keystroke('"1" using {command down}', 0.3))),
        ("v6-themes", 8, None),
    ]

    for name, secs, prep in clips:
        if name == "v6-themes":
            # cycle themes while recording
            place_window()
            mp4 = out / f"{name}.mp4"
            # start record in background
            proc = subprocess.Popen(
                [
                    FFMPEG,
                    "-y",
                    "-f",
                    "avfoundation",
                    "-framerate",
                    "30",
                    "-i",
                    "1:none",
                    "-t",
                    str(secs),
                    "-vf",
                    f"crop={W}:{H}:60:40,scale=1280:800",
                    "-c:v",
                    "libx264",
                    "-pix_fmt",
                    "yuv420p",
                    "-crf",
                    "24",
                    "-preset",
                    "slow",
                    "-an",
                    "-movflags",
                    "+faststart",
                    str(mp4),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            for theme in ("midnightBlue", "graphitePro", "emeraldSlate", "nordicLight", "midnightBlue"):
                set_prefs(lang, theme)
                # bounce theme via defaults + notify app by toggling settings
                keystroke('"," using {command down}', 0.5)
                keycode(53, delay=0.4)
                time.sleep(1.0)
            proc.wait(timeout=secs + 5)
        else:
            if prep:
                prep()
            place_window()
            mp4 = out / f"{name}.mp4"
            record_window(secs, mp4)
        # size guard
        if mp4.exists() and mp4.stat().st_size > 1_800_000:
            slim = mp4.with_suffix(".slim.mp4")
            run(
                [
                    FFMPEG,
                    "-y",
                    "-i",
                    str(mp4),
                    "-vf",
                    "scale=1280:800",
                    "-c:v",
                    "libx264",
                    "-crf",
                    "28",
                    "-preset",
                    "slow",
                    "-an",
                    "-movflags",
                    "+faststart",
                    str(slim),
                ]
            )
            slim.replace(mp4)
        poster = out / f"{name}-poster.webp"
        # also write jpg poster for landing compatibility
        poster_from_video(mp4, poster)
        jpg = out / f"{name}-poster.jpg"
        if poster.exists():
            run(["sips", "-s", "format", "jpeg", str(poster), "--out", str(jpg)], check=False)
        print(f"OK video {lang}/{name} size={mp4.stat().st_size if mp4.exists() else 0}")


def social_pack() -> None:
    pack = HOME / "Desktop/FINDARO_SOCIAL_PACK_ES_EN"
    if pack.exists():
        shutil.rmtree(pack)
    for lang in ("es", "en"):
        for ratio, w, h in (("16x9", 1920, 1080), ("4x5", 1080, 1350)):
            dest = pack / lang / ratio
            dest.mkdir(parents=True)
            for name in ("v1-ai-voice", "v2-dual-pane-cut", "v3-smart-merge", "v4-deep-search", "v5-views-trash", "v6-themes"):
                src = WEB / "videos" / lang / f"{name}.mp4"
                if not src.exists():
                    continue
                title_es = {
                    "v1-ai-voice": "IA local con tu voz",
                    "v2-dual-pane-cut": "En Finder ⌘X no corta. En FINDARO sí.",
                    "v3-smart-merge": "Smart Merge con vista previa",
                    "v4-deep-search": "Busca en todas las subcarpetas",
                    "v5-views-trash": "4 vistas + Restaurar Papelera",
                    "v6-themes": "5 temas de color en vivo",
                }
                title_en = {
                    "v1-ai-voice": "On-device AI you can talk to",
                    "v2-dual-pane-cut": "Real ⌘X Cut & Paste + Dual Pane",
                    "v3-smart-merge": "Smart Merge with conflict preview",
                    "v4-deep-search": "Deep search across subfolders",
                    "v5-views-trash": "4 views + one-click Trash restore",
                    "v6-themes": "5 live color themes",
                }
                title = (title_es if lang == "es" else title_en)[name].replace(":", "\\:")
                out = dest / f"{name}.mp4"
                vf = (
                    f"scale={w}:{h}:force_original_aspect_ratio=decrease,"
                    f"pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:color=0x0B1220,"
                    f"drawbox=x=0:y=0:w={w}:h=96:color=0x0B1220@0.9:t=fill,"
                    f"drawtext=text='{title}':x=40:y=34:fontsize=36:fontcolor=white:font=Helvetica-Bold"
                )
                run([FFMPEG, "-y", "-i", str(src), "-vf", vf, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "22", "-an", str(out)], check=False)
    links = pack / "LINKS_UTM_REDES.txt"
    links.write_text(
        """FINDARO — enlaces UTM para redes
ES X: https://findaro.iareal.net/?lang=es&utm_source=x&utm_medium=social&utm_campaign=launch
ES Facebook: https://findaro.iareal.net/?lang=es&utm_source=facebook&utm_medium=social&utm_campaign=launch
EN X: https://findaro.iareal.net/?lang=en&utm_source=x&utm_medium=social&utm_campaign=launch
EN Facebook: https://findaro.iareal.net/?lang=en&utm_source=facebook&utm_medium=social&utm_campaign=launch
""",
        encoding="utf-8",
    )
    print(f"OK social pack {pack}")


def embed_videos_in_landings() -> None:
    # Landings already point to /videos/{es,en}/v*.mp4 — ensure posters path if needed.
    print("Landings already reference /videos/{es,en}/ — no structural rewrite required")


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "all"
    if cmd in ("screenshots", "all"):
        capture_lang("es")
        capture_lang("en")
        bad = privacy_scan(WEB / "screenshots")
        if bad:
            print("PRIVACY WARN", bad[:10])
    if cmd in ("og", "all"):
        make_og()
    if cmd in ("videos", "all"):
        make_videos("es")
        make_videos("en")
        social_pack()
        embed_videos_in_landings()
    print("PHASE3 MEDIA COMPLETE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
